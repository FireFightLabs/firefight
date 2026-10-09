# Something Halon or a person taught the workspace, such as which database is production. It is about a resource on the
# map, a catalog entry, or the whole workspace, and it keeps where it came from. What Halon learns is used at once and
# marked unconfirmed, a person confirms or rejects it, and a rejected one is kept so the same wrong idea is not learned
# again. Halon treats every memory as a hunch to check, never as proof.
class Chat::Memory < ApplicationRecord
  include Chat::SecretFree

  self.table_name = "chat_memories"

  STATE_UNCONFIRMED = "unconfirmed".freeze
  STATE_CONFIRMED = "confirmed".freeze
  # Something showed it may be wrong, so it is not used until a person decides.
  STATE_DISPUTED = "disputed".freeze
  # What it is about changed or went away, so it needs a fresh look.
  STATE_OUTDATED = "outdated".freeze
  STATE_REJECTED = "rejected".freeze
  # Nobody confirmed it within the workspace's window, so it stopped being used.
  STATE_EXPIRED = "expired".freeze
  STATES = [ STATE_UNCONFIRMED, STATE_CONFIRMED, STATE_DISPUTED, STATE_OUTDATED, STATE_REJECTED, STATE_EXPIRED ].freeze
  # What Halon is handed. Disputed, rejected and expired memories are kept for people, never used.
  USED_STATES = [ STATE_CONFIRMED, STATE_UNCONFIRMED, STATE_OUTDATED ].freeze
  # Waiting on a person to say whether it is right. An expired one was set aside already.
  AWAITING_STATES = [ STATE_UNCONFIRMED, STATE_DISPUTED, STATE_OUTDATED ].freeze
  SUBJECT_TYPES = [ ResourceMap::Resource.name, CatalogEntry.name ].freeze
  TEXT_LIMIT = 500
  # How many memories a chat or a run starts with, and recall answers with, so memory never crowds out the question.
  STARTING_LIMIT = 20

  # Why a memory was flagged outdated. Only the sweep's own flag for a removed resource is lifted when it comes back.
  OUTDATED_REMOVED = "removed".freeze
  OUTDATED_RENAMED = "renamed".freeze
  OUTDATED_ARCHIVED = "archived".freeze
  OUTDATED_CAUSES = [ OUTDATED_REMOVED, OUTDATED_RENAMED, OUTDATED_ARCHIVED ].freeze

  # How a run's starting memory changed when a person deleted it, beside the state keys of the other changes.
  CHANGE_DELETED = "deleted".freeze

  # The Memory page shows the memory this names, so a search result can link straight to it.
  QUERY_PARAM = "memory".freeze

  # The days a workspace can let an unconfirmed memory wait for a person before it stops being used.
  EXPIRY_CHOICES = [ 30, 60, 90, 180 ].freeze

  encrypts :text

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :confirmed_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :rejected_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :replaced_by, class_name: "Chat::Memory", optional: true
  # The newer memory that disputed this one by saying otherwise. A person's answer settles both.
  belongs_to :contradicted_by, class_name: "Chat::Memory", optional: true
  # The completed postmortem that made the last decision on it, whether or not a person completed it.
  belongs_to :decided_by_postmortem, class_name: "Postmortem", optional: true

  validates :text, presence: true, length: { maximum: TEXT_LIMIT }
  validates :state, inclusion: { in: STATES }
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true
  validates :outdated_cause, inclusion: { in: OUTDATED_CAUSES }, allow_nil: true
  # What each decision may move a memory from. A rejected memory stays rejected.
  CONFIRMABLE_FROM = STATES - [ STATE_REJECTED, STATE_CONFIRMED ]
  REJECTABLE_FROM = STATES - [ STATE_REJECTED ]
  # A postmortem confirms what Halon learned, never what Halon disputed or a person rejected.
  POSTMORTEM_CONFIRMS_FROM = [ STATE_UNCONFIRMED, STATE_OUTDATED, STATE_EXPIRED ].freeze

  # What learning a fact came to. Saved, already known, refused because a person rejected it before, or refused because
  # it is something memory never holds.
  LEARNED_SAVED = :saved
  LEARNED_KNOWN = :known
  LEARNED_REJECTED = :rejected
  LEARNED_REFUSED = :refused
  # contradicted holds the memories a saved one contradicted, each now disputed until a person decides.
  Learned = Data.define(:outcome, :memory, :reason, :contradicted) do
    def initialize(outcome:, memory: nil, reason: nil, contradicted: []) = super
  end
  # How many memories about the same thing the judge reads beside a new fact, the most recently changed first.
  JUDGED_LIMIT = 30
  # Judged against a new fact. A disputed memory already waits on a person, so it is left alone.
  JUDGED_STATES = [ STATE_UNCONFIRMED, STATE_CONFIRMED, STATE_OUTDATED, STATE_EXPIRED, STATE_REJECTED ].freeze
  # A judge that fails with one of these is read as having judged nothing.
  JUDGE_ERRORS = [ FirefightAi::Error, RubyLLM::Error, RubyLLM::ConfigurationError ].freeze
  # What a new fact may dispute.
  CONTRADICTABLE_FROM = [ STATE_UNCONFIRMED, STATE_CONFIRMED, STATE_OUTDATED ].freeze

  # What a name given for a memory's subject came to, the subject or why none was picked.
  Named = Data.define(:subject, :refusal)
  # What recall found, the best first, and how many more matched than it shows.
  Recalled = Data.define(:memories, :more)
  # How a starting memory changed since a run began, as a key to tell it once, the mark in its facts and the note it reads.
  Change = Data.define(:key, :mark, :note)

  scope :in_use, -> { where(state: USED_STATES) }
  # Every memory in workspace except those about a resource outside principal's map reach, which reads as never there.
  scope :visible_to, ->(principal, workspace) {
    where(workspace: workspace).where("chat_memories.subject_type IS DISTINCT FROM ?", ResourceMap::Resource.name)
      .or(where(workspace: workspace, subject_type: ResourceMap::Resource.name,
                subject_id: ResourceMap::Resource.visible_to(principal, workspace).select(:id)))
  }
  scope :most_trusted_first, -> { order(Arel.sql(sanitize_sql_array([ "CASE state WHEN ? THEN 0 ELSE 1 END", STATE_CONFIRMED ])), created_at: :desc) }

  # The memories a chat or a run starts with: those about what it touches, then the workspace wide ones.
  def self.starting_with(workspace, subjects, principal:)
    about = subjects.compact.group_by { |subject| subject.class.name }.map { |type, found| where(subject_type: type, subject_id: found.map(&:id)) }
    scope = visible_to(principal, workspace).in_use
    relevant = about.inject(scope.where(subject_id: nil)) { |union, part| union.or(scope.merge(part)) }
    relevant.includes(:subject, :confirmed_by).most_trusted_first.limit(STARTING_LIMIT).to_a
  end

  # Memories a chat or run was handed at its start count as used, once for each chat or run however many turns it takes.
  def self.handed_to!(memories, owner)
    return if memories.empty?

    rows = memories.map { |memory| { memory_id: memory.id, owner_type: owner.class.polymorphic_name, owner_id: owner.id, created_at: Time.current } }
    counted = Chat::MemoryUse.insert_all(rows, unique_by: :index_chat_memory_uses_once_per_owner, returning: :memory_id).rows.flatten
    where(id: counted).update_all([ "use_count = use_count + 1, last_used_at = ?", Time.current ]) if counted.any?
  end

  # What a memory is about, named the way a person or Halon would. A resource on the map by its name, provider id or
  # Firefight id, or a catalog entry by its name, slug or id. A name nothing has, or one several things share, is
  # refused with a sentence, never guessed. removed also looks among resources gone from the map, when none present has it.
  # Only resources principal may read count, so one outside its reach is refused as a name nothing has.
  def self.subject_named(workspace, name, principal:, removed: false)
    wanted = name.to_s.strip
    return Named.new(subject: nil, refusal: nil) if wanted.empty?

    visible = ResourceMap::Resource.visible_to(principal, workspace)
    found = named_candidates(workspace, visible, wanted, removed: false)
    found = named_candidates(workspace, visible, wanted, removed: true) if found.empty? && removed
    return Named.new(subject: found.sole, refusal: nil) if found.one?
    return Named.new(subject: nil, refusal: "Nothing called #{wanted} is on the map or in the catalog.") if found.empty?

    choices = found.map { |subject| "#{subject.id} (#{subject_label(subject)})" }.join(", ")
    Named.new(subject: nil, refusal: "More than one thing is called #{wanted}: #{choices}. Name it by its id.")
  end

  def self.named_candidates(workspace, visible, wanted, removed:)
    resources = removed ? visible.where.not(removed_at: nil) : visible.where(removed_at: nil)
    entries = removed ? CatalogEntry.none : workspace.catalog_entries.active
    lowered = wanted.downcase
    by_id = wanted.match?(CatalogEntry::ReferenceManagement::UUID_FORMAT)
    [
      *(by_id ? resources.where(id: wanted) : ResourceMap::Resource.named(workspace, wanted).merge(resources)).to_a,
      *(by_id ? entries.where(id: wanted) : entries.where("lower(name) = :wanted OR lower(slug) = :wanted", wanted: lowered)).includes(:catalog_type).to_a
    ]
  end
  private_class_method :named_candidates

  def self.subject_label(subject)
    case subject
    when CatalogEntry then "#{subject.catalog_type.name} #{subject.name} in the catalog"
    else "#{ResourceMap.provider_name(subject.provider)} #{subject.kind} #{subject.name} on the map"
    end
  end

  # What a memory or instructions can be about, for a picker: the catalog's active entries, then the resources principal
  # reads on the map, so the picker never names one outside their environments.
  def self.subject_choices(workspace, principal:)
    workspace.catalog_entries.active.includes(:catalog_type).order(:name).to_a +
      ResourceMap::Resource.visible_to(principal, workspace).present.order(:name).to_a
  end

  # A subject as the dashboard names it, its type and id, such as "CatalogEntry:<id>". Instructions use the same keys.
  def self.subject_key(subject) = subject && "#{subject.class.name}:#{subject.id}"

  # The subject a key names in this workspace, nil for a blank key. Raises RecordNotFound for anything else, a resource
  # outside principal's reach included.
  def self.subject_for_key(workspace, key, principal:)
    type, id = key.to_s.split(":", 2)
    return nil if type.blank?

    case type
    when CatalogEntry.name then workspace.catalog_entries.active.find(id)
    when ResourceMap::Resource.name then ResourceMap::Resource.visible_to(principal, workspace).present.find(id)
    else raise ActiveRecord::RecordNotFound, "No subject of type #{type}"
    end
  end

  # The one way a fact is learned, from a chat, a run or an ended incident. The same fact about the same thing, in any
  # wording, is never saved twice, and one a person rejected is never learned again. A vouched fact is confirmed by
  # whoever taught it. A live value or a fact about a person is refused with why. judge (FirefightAi::MemoryJudge) reads
  # the new fact against what is remembered about the same thing, so a fact in other words is known and one that says
  # otherwise disputes what it contradicts, with contradiction as the reason. A judge that fails changes nothing.
  def self.learn!(workspace, text:, subject:, source:, added_by: nil, vouched: false, judge: nil, contradiction: nil)
    # Read with any credential already redacted, so one is refused as a secret by validation rather than as an address.
    refusal = Chat::Memory::Screening.refusal(workspace, Chat::SecretFree.redacted(text.to_s))
    return Learned.new(outcome: LEARNED_REFUSED, reason: refusal) if refusal

    around = where(workspace: workspace, subject: subject).order(updated_at: :desc).to_a
    signature = Chat::Memory::Words.signature(text)
    known = around.find { |memory| Chat::Memory::Words.signature(memory.text) == signature }
    verdicts = known ? {} : judged(judge, text, around.select { |memory| JUDGED_STATES.include?(memory.state) }.first(JUDGED_LIMIT))
    same = around.select { |memory| verdicts[memory.id] == FirefightAi::Schemas::MemoryVerdicts::SAME }
    known ||= same.find { |memory| memory.state != STATE_REJECTED } || same.first
    return already_known(known) if known

    confirmer = added_by if vouched
    transaction do
      memory = create!(workspace: workspace, text: text, subject: subject, source: source, added_by: added_by,
                       state: confirmer ? STATE_CONFIRMED : STATE_UNCONFIRMED, confirmed_by: confirmer, confirmed_at: (Time.current if confirmer))
      contradicted = around.select { |each| verdicts[each.id] == FirefightAi::Schemas::MemoryVerdicts::CONTRADICTS }
                           .select { |each| each.contradicted!(memory, reason: contradiction.presence || "Halon learned \"#{text}\", which says otherwise.") }
      Learned.new(outcome: LEARNED_SAVED, memory: memory, contradicted: contradicted)
    end
  end

  def self.already_known(known)
    return Learned.new(outcome: LEARNED_REJECTED, memory: known) if known.state == STATE_REJECTED

    # Learned again, so it is worth another wait for a person, and an unconfirmed one waits from now.
    if known.state == STATE_EXPIRED
      known.revive!
    elsif known.state == STATE_UNCONFIRMED
      known.touch
    end
    Learned.new(outcome: LEARNED_KNOWN, memory: known)
  end
  private_class_method :already_known

  # Each judged memory's id with same or contradicts. A judge that cannot answer, such as when the workspace's account is
  # out of credit or its model is not set up, leaves the fact to be saved as if nothing were remembered.
  def self.judged(judge, text, memories)
    return {} if judge.nil? || memories.empty?

    known = memories.map { |memory| FirefightAi::MemoryJudge::Known.new(id: memory.id, text: memory.text) }
    judge.verdicts(fact: text, known: known).to_h { |verdict| [ verdict.id, verdict.verdict ] }
  rescue *JUDGE_ERRORS => error
    Rails.logger.info({ event: "memory.judge_failed", workspace_id: memories.first.workspace_id, error: error.class.name }.to_json)
    {}
  end
  private_class_method :judged

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

  # The workspace's memories in use about a subject, or matching the words asked. The best come first, ranked by how many
  # of the words they hold and how rare each is with a boost for the whole phrase, then confirmed first, then newest.
  def self.recall(workspace, principal:, subject: nil, query: nil)
    found = visible_to(principal, workspace).in_use.includes(:subject, :confirmed_by)
    found = found.where(subject: subject) if subject
    found = found.to_a
    ranked = if Chat::Memory::Words.stems(query).empty?
      found.sort_by { |memory| [ memory.confirmed? ? 0 : 1, -memory.created_at.to_f ] }
    else
      matching(found, query)
    end
    Recalled.new(memories: ranked.first(STARTING_LIMIT), more: [ ranked.size - STARTING_LIMIT, 0 ].max)
  end

  # Those of memories that hold any of the words asked, the best first, as recall ranks them. Nothing when no word counts.
  def self.matching(memories, query)
    asked = Chat::Memory::Words.stems(query)
    return [] if asked.empty?

    scored = scores(memories, asked, Chat::Memory::Words.squished(query))
    memories.select { |memory| scored[memory.id].positive? }
            .sort_by { |memory| [ -scored[memory.id], memory.confirmed? ? 0 : 1, -memory.created_at.to_f ] }
  end

  def self.scores(memories, asked, phrase)
    rarity = Hash.new(0)
    memories.each { |memory| Chat::Memory::Words.stems(memory.text).uniq.each { |word| rarity[word] += 1 } }
    phrase = nil if asked.uniq.size < 2
    memories.to_h { |memory| [ memory.id, Chat::Memory::Words.score(memory.text, asked, phrase, rarity: rarity, total: memories.size) ] }
  end
  private_class_method :scores

  # How a run's starting memory changed since it began, or nil while it still holds. memory is nil once deleted.
  def self.change_since_start(id, memory)
    return Change.new(key: CHANGE_DELETED, mark: "[deleted since this run started]", note: "Memory #{id} was deleted by a person since you started. Do not rely on it.") unless memory

    case memory.state
    when STATE_REJECTED
      if memory.replaced_by
        Change.new(key: "corrected:#{memory.replaced_by_id}", mark: "[corrected since this run started: #{memory.replaced_by.text}]",
                   note: "Memory #{id} was corrected by #{memory.decider} since you started. What is right instead: #{memory.replaced_by.text}")
      else
        Change.new(key: STATE_REJECTED, mark: "[rejected since this run started]",
                   note: "Memory #{id} was rejected by #{memory.decider} since you started#{": #{memory.state_reason}" if memory.state_reason.present?}. Do not rely on it.")
      end
    when STATE_DISPUTED
      Change.new(key: STATE_DISPUTED, mark: "[disputed since this run started: #{memory.state_reason}]",
                 note: "Memory #{id} was disputed since you started: #{memory.state_reason} Do not rely on it until a person decides.")
    when STATE_EXPIRED
      Change.new(key: STATE_EXPIRED, mark: "[no longer in use since this run started]",
                 note: "Memory #{id} stopped being used since you started, since nobody confirmed it in time. Treat it as unchecked.")
    end
  end

  # What a memory is about changed, renamed, archived or gone, so what it says may no longer hold. One guarded update
  # over one subject or several, and a disputed, rejected or expired memory is left as it was. It keeps what it was so
  # the flag can be lifted.
  def self.flag_outdated!(subject, reason, cause:)
    where(subject: subject, state: [ STATE_UNCONFIRMED, STATE_CONFIRMED ])
      .update_all([ "outdated_from = state, state = ?, state_reason = ?, outdated_cause = ?, updated_at = ?", STATE_OUTDATED, reason, cause, Time.current ])
  end

  # The cause is gone, such as a removed resource the map sees again, so a memory still flagged for it goes back to what
  # it was. A memory a person decided on since is no longer outdated, so it is never touched.
  def self.clear_outdated!(subject, cause:)
    where(subject: subject, state: STATE_OUTDATED, outdated_cause: cause).where.not(outdated_from: nil)
      .update_all([ "state = outdated_from, state_reason = NULL, outdated_from = NULL, outdated_cause = NULL, updated_at = ?", Time.current ])
  end

  # An unconfirmed memory nobody confirmed within the workspace's window stops being used, counted from when it was
  # last learned, learned again or came back into use. Returns how many expired.
  def self.expire!(workspace)
    days = workspace.memory_expiry_days
    return 0 unless days

    where(workspace: workspace, state: STATE_UNCONFIRMED).where(updated_at: ...days.days.ago)
      .update_all(state: STATE_EXPIRED, state_reason: "Nobody confirmed it within #{days} days.", updated_at: Time.current)
  end

  def confirmed? = state == STATE_CONFIRMED

  def in_use? = USED_STATES.include?(state)

  def awaiting_decision? = AWAITING_STATES.include?(state)

  # A lesson as it is shown beside the answer it came from.
  def lesson = { id: id, text: text, confirmed: confirmed? }

  def about = subject.respond_to?(:name) ? subject.name : nil

  # A resource this memory is about that is gone from the map.
  def about_removed? = subject.is_a?(ResourceMap::Resource) && subject.removed_at.present?

  # How Halon reads it: the fact, what it is about, and whether anyone vouched for it.
  def line
    "#{id} (#{[ about, trust ].compact.join(', ')}): #{text}"
  end

  # Who stands behind it, in words. Only a person is ever named, and a postmortem nobody signed off is never one.
  def trust
    return state unless confirmed?
    return "confirmed by #{confirmed_by.display_name}" if confirmed_by
    return "confirmed by a postmortem" if decided_by_postmortem_id

    "confirmed"
  end

  # Where it came from, said to viewer, such as "your chat", "a chat with Ana", "INC-12" or "the INC-12 investigation".
  def origin_for(viewer)
    case source
    when Conversation then source.started_by == viewer ? "your chat" : "a chat with #{source.started_by.try(:display_name) || 'someone'}"
    when Investigation then source.incident ? "the #{source.incident.identifier} investigation" : "an investigation"
    when Incident then source.identifier
    when WorkspaceMembership then source == viewer ? "what you wrote on the Memory page" : "what #{source.display_name} wrote on the Memory page"
    else "an earlier chat or incident"
    end
  end

  # Who stood behind it, said to viewer, such as "confirmed by you" or "not confirmed yet". A dispute leaves who
  # confirmed it, so a card asking about one still says.
  def trust_for(viewer)
    return "confirmed by you" if confirmed_by && confirmed_by == viewer
    return "confirmed by #{confirmed_by.display_name}" if confirmed_by
    return "confirmed by a postmortem" if confirmed_at && decided_by_postmortem_id

    "not confirmed yet"
  end

  # How a person settled it, said to viewer, or nil while it waits.
  def decided_for(viewer)
    person = rejected_by || confirmed_by
    who = person && person == viewer ? "you" : decider
    case state
    when STATE_CONFIRMED then "Kept as still right by #{who}."
    when STATE_REJECTED then replaced_by ? "Marked not right by #{who}. Halon now remembers \"#{replaced_by.text}\" instead." : "Marked not right by #{who}."
    end
  end

  # Who made the last decision on it, in words.
  def decider
    person = rejected_by || confirmed_by
    return person.display_name if person
    return "a postmortem" if decided_by_postmortem_id

    "a person"
  end

  # Why a person cannot confirm it now, or nil. The page and the controller ask this rather than reading the state.
  def confirm_blocked_reason
    return "It is confirmed already." if state == STATE_CONFIRMED
    return "It was rejected. Add it again if it is right after all." unless CONFIRMABLE_FROM.include?(state)

    nil
  end

  def reject_blocked_reason = ("It was rejected already." unless REJECTABLE_FROM.include?(state))

  # What deleting it means, for the dialog that asks first and the notice after.
  def delete_consequence
    return "Halon has nothing left to say the wording was wrong, so it may learn it again." if state == STATE_REJECTED

    "Halon stops using it, and nothing keeps where it came from."
  end

  # A person saying it is wrong, or a postmortem nobody signed off when by is nil. Kept as rejected with who and why,
  # and a correction replaces it as confirmed by them.
  # A memory a newer one contradicted is settled with it: a person saying it is not right takes the newer one as
  # what is right, confirmed by them, and a correction replaces both.
  def reject!(by:, reason:, correction: nil, postmortem: nil)
    transaction do
      if !decide!(STATE_REJECTED, from: REJECTABLE_FROM, state_reason: reason.presence, rejected_by_id: by&.id, rejected_at: Time.current,
                                  decided_by_postmortem_id: postmortem&.id)
        nil
      elsif correction.blank?
        contradicted_by.confirm!(by: by, reason: "It replaced \"#{text}\", which #{by.display_name} marked not right.") if by && contradicted_by
        update_columns(replaced_by_id: contradicted_by_id) if by && contradicted_by&.confirmed?
        self
      else
        replacement = self.class.create!(workspace: workspace, text: correction, subject: subject, state: STATE_CONFIRMED, source: source,
                                         added_by: by, confirmed_by: by, confirmed_at: Time.current, decided_by_postmortem: postmortem)
        update_columns(replaced_by_id: replacement.id)
        contradicted_by&.reject!(by: by, reason: "#{by&.display_name || 'A postmortem'} corrected what it contradicted instead.")
        replacement
      end
    end
  end

  # A person vouching for it. A rejected memory stays rejected. One a newer memory contradicted is still right, so the
  # newer one is rejected.
  def confirm!(by:, reason: nil)
    transaction do
      confirmed = decide!(STATE_CONFIRMED, from: CONFIRMABLE_FROM, confirmed_by_id: by&.id, confirmed_at: Time.current, state_reason: reason,
                                           decided_by_postmortem_id: nil)
      contradicted_by&.reject!(by: by, reason: "#{by&.display_name || 'A person'} confirmed \"#{text}\" is still right.") if confirmed
      confirmed
    end
  end

  # A completed postmortem agreeing with what Halon learned, credited to whoever completed it when that was a person.
  def confirm_from_postmortem!(postmortem, by:)
    decide!(STATE_CONFIRMED, from: POSTMORTEM_CONFIRMS_FROM, confirmed_by_id: by&.id, confirmed_at: Time.current,
                             state_reason: "The #{postmortem.incident.identifier} postmortem agrees", decided_by_postmortem_id: postmortem.id)
  end

  def dispute!(reason)
    decide!(STATE_DISPUTED, from: CONTRADICTABLE_FROM, state_reason: reason)
  end

  # A newer memory says otherwise, so this one waits on a person, who settles both at once.
  def contradicted!(challenger, reason:)
    decide!(STATE_DISPUTED, from: CONTRADICTABLE_FROM, state_reason: reason, contradicted_by_id: challenger.id)
  end

  # An expired memory learned again goes back to waiting for a person, with a fresh window.
  def revive!
    decide!(STATE_UNCONFIRMED, from: [ STATE_EXPIRED ], state_reason: nil)
  end

  def used!
    self.class.where(id: id).update_all([ "use_count = use_count + 1, last_used_at = ?", Time.current ])
  end

  private

  # Guarded, so two people deciding on the same memory at once cannot both land. A decision ends any outdated flag.
  def decide!(state, from:, **columns)
    moved = self.class.where(id: id, state: from)
                      .update_all(columns.merge(state: state, outdated_from: nil, outdated_cause: nil, updated_at: Time.current)) > 0
    reload
    moved
  end
end
