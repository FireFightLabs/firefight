# Something Halon or a person taught the workspace, such as which database is production. It is about a resource on the
# map, a catalog entry, or the whole workspace, and it keeps where it came from. What Halon learns is used at once and
# marked unconfirmed, a person confirms or rejects it, and a rejected one is kept so the same wrong idea is not learned
# again. Halon treats every memory as a hunch to check, never as proof.
class Chat::Memory < ApplicationRecord
  self.table_name = "chat_memories"

  STATE_UNCONFIRMED = "unconfirmed".freeze
  STATE_CONFIRMED = "confirmed".freeze
  # Something showed it may be wrong, so it is not used until a person decides.
  STATE_DISPUTED = "disputed".freeze
  # What it is about changed or went away on the map, so it needs a fresh look.
  STATE_OUTDATED = "outdated".freeze
  STATE_REJECTED = "rejected".freeze
  STATES = [ STATE_UNCONFIRMED, STATE_CONFIRMED, STATE_DISPUTED, STATE_OUTDATED, STATE_REJECTED ].freeze
  # What Halon is handed. Disputed and rejected memories are kept for people, never used.
  USED_STATES = [ STATE_CONFIRMED, STATE_UNCONFIRMED, STATE_OUTDATED ].freeze
  SUBJECT_TYPES = [ ResourceMap::Resource.name, CatalogEntry.name ].freeze
  TEXT_LIMIT = 500
  # How many memories a chat or a run starts with, so memory never crowds out the question.
  STARTING_LIMIT = 20

  encrypts :text

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :confirmed_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :rejected_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :replaced_by, class_name: "Chat::Memory", optional: true

  validates :text, presence: true, length: { maximum: TEXT_LIMIT }
  validates :state, inclusion: { in: STATES }
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true
  validate :holds_no_secret

  # A memory reaches every later prompt, so anything that looks like a credential is refused rather than kept. The
  # patterns are the transcript scrubber's, plus a connection string carrying a password.
  CREDENTIAL_URL = %r{\b[a-z][a-z0-9+.-]*://[^\s:@/]+:[^\s@/]+@}i
  SECRET_PATTERNS = IncidentTranscriptMessage::Scrubbing::SECRET_PATTERNS.merge(credential_url: CREDENTIAL_URL).freeze

  scope :in_use, -> { where(state: USED_STATES) }
  # Confirmed first, then the newest, since a person vouched for the first and the second is the freshest guess.
  scope :most_trusted_first, -> { order(Arel.sql("CASE state WHEN 'confirmed' THEN 0 ELSE 1 END"), created_at: :desc) }

  # The memories a chat or a run starts with: those about what it touches, then the workspace wide ones.
  def self.starting_with(workspace, subjects)
    about = subjects.compact.group_by { |subject| subject.class.name }.map { |type, found| where(subject_type: type, subject_id: found.map(&:id)) }
    scope = where(workspace: workspace).in_use
    relevant = about.inject(scope.where(subject_id: nil)) { |union, part| union.or(scope.merge(part)) }
    relevant.includes(:subject).most_trusted_first.limit(STARTING_LIMIT).to_a
  end

  # What a memory is about, named the way a person or Halon would: a resource on the map by its name or provider id,
  # else a catalog entry by its name or slug. nil when neither matches.
  def self.subject_named(workspace, name)
    return nil if name.blank?

    ResourceMap::Resource.named(workspace, name).present.first ||
      workspace.catalog_entries.active.where("lower(name) = :wanted OR lower(slug) = :wanted", wanted: name.to_s.strip.downcase).first
  end

  # A subject as the dashboard names it, its type and id, such as "CatalogEntry:<id>". Instructions use the same keys.
  def self.subject_key(subject) = subject && "#{subject.class.name}:#{subject.id}"

  # The subject a key names in this workspace, nil for a blank key. Raises RecordNotFound for anything else.
  def self.subject_for_key(workspace, key)
    type, id = key.to_s.split(":", 2)
    return nil if type.blank?

    case type
    when CatalogEntry.name then workspace.catalog_entries.active.find(id)
    when ResourceMap::Resource.name then ResourceMap::Resource.present.where(workspace: workspace).find(id)
    else raise ActiveRecord::RecordNotFound, "No subject of type #{type}"
    end
  end

  # A fact a person wrote down themselves, so it counts as confirmed by them from the start.
  def self.written_by!(member, text:, subject:)
    create!(workspace: member.workspace, text: text, subject: subject, state: STATE_CONFIRMED, source: member,
            added_by: member, confirmed_by: member, confirmed_at: Time.current)
  end

  # What an incident touches: the catalog services named on it and the resources those services run on.
  def self.subjects_for(incident)
    return [] unless incident

    services = incident.catalog_services
    services + ResourceMap::Resource.present.joins(:entry_links).where(resource_map_entry_links: { catalog_entry_id: services.map(&:id) }).distinct.to_a
  end

  # The workspace's memories in use, matched by what they are about and by any of the words asked. Text is encrypted,
  # so the words are matched here rather than in SQL, over one workspace's memories.
  def self.recall(workspace, subject: nil, query: nil)
    found = where(workspace: workspace).in_use.includes(:subject, :confirmed_by).most_trusted_first
    found = found.where(subject: subject) if subject
    words = query.to_s.downcase.split(/\W+/).reject { |word| word.length < 3 }
    found = found.to_a
    found = found.select { |memory| words.any? { |word| memory.text.downcase.include?(word) } } if words.any?
    found.first(STARTING_LIMIT)
  end

  def confirmed? = state == STATE_CONFIRMED

  def about = subject.respond_to?(:name) ? subject.name : nil

  # How Halon reads it: the fact, what it is about, and whether anyone vouched for it.
  def line
    trust = confirmed? ? "confirmed by #{confirmed_by&.display_name || 'a person'}" : state
    "#{id} (#{[ about, trust ].compact.join(', ')}): #{text}"
  end

  # Guarded, so two people deciding on the same memory at once cannot both land.
  # A person saying it is wrong. The memory is kept as rejected with who and why, so it is never learned again, and a
  # correction, when they give one, replaces it as confirmed by them.
  def reject!(by:, reason:, correction: nil)
    transaction do
      if !decide!(STATE_REJECTED, from: STATES - [ STATE_REJECTED ], state_reason: reason.presence, rejected_by_id: by&.id, rejected_at: Time.current)
        nil
      elsif correction.blank?
        self
      else
        replacement = self.class.create!(workspace: workspace, text: correction, subject: subject, state: STATE_CONFIRMED, source: source,
                                         added_by: by, confirmed_by: by, confirmed_at: Time.current)
        update_columns(replaced_by_id: replacement.id)
        replacement
      end
    end
  end

  # What a memory is about changed on the map, renamed or gone, so what it says may no longer hold. One guarded update,
  # and a disputed or rejected memory is left as a person left it.
  def self.flag_outdated!(subject, reason)
    where(subject: subject, state: [ STATE_UNCONFIRMED, STATE_CONFIRMED ])
      .update_all(state: STATE_OUTDATED, state_reason: reason, updated_at: Time.current)
  end

  # A person, or a published postmortem when by is nil, vouching for it. A rejected memory stays rejected.
  def confirm!(by:, reason: nil)
    decide!(STATE_CONFIRMED, from: STATES - [ STATE_REJECTED, STATE_CONFIRMED ], confirmed_by_id: by&.id, confirmed_at: Time.current,
                             state_reason: reason)
  end

  def dispute!(reason)
    decide!(STATE_DISPUTED, from: [ STATE_UNCONFIRMED, STATE_CONFIRMED, STATE_OUTDATED ], state_reason: reason)
  end

  def used!
    self.class.where(id: id).update_all([ "use_count = use_count + 1, last_used_at = ?", Time.current ])
  end

  private

  def holds_no_secret
    found = SECRET_PATTERNS.keys.find { |name| text.to_s.match?(SECRET_PATTERNS[name]) }
    errors.add(:text, "looks like it holds a secret (#{found.to_s.humanize(capitalize: false)}), so it is not remembered") if found
  end

  def decide!(state, from:, **columns)
    moved = self.class.where(id: id, state: from).update_all(columns.merge(state: state, updated_at: Time.current)) > 0
    reload
    moved
  end
end
