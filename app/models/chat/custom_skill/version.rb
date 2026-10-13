# One version of a workspace's skill: when it is used, the tools it needs and its steps, numbered in order, with who
# wrote it (a person, Halon or Firefight's library), why, and the version it came from. One version is live. Halon's
# proposals wait as versions of their own until a person accepts or dismisses them. A version that was live never
# changes again, so the history reads true.
class Chat::CustomSkill::Version < ApplicationRecord
  self.table_name = "chat_custom_skill_versions"

  STATUS_LIVE = "live".freeze
  # Was live, until a later version replaced it.
  STATUS_RETIRED = "retired".freeze
  # Halon's, waiting on a person.
  STATUS_PROPOSED = "proposed".freeze
  STATUS_DISMISSED = "dismissed".freeze
  # Halon's, which a person edited before accepting, so the version after it is what went live.
  STATUS_EDITED = "edited".freeze
  STATUSES = [ STATUS_LIVE, STATUS_RETIRED, STATUS_PROPOSED, STATUS_DISMISSED, STATUS_EDITED ].freeze

  AUTHOR_PERSON = "person".freeze
  AUTHOR_HALON = "halon".freeze
  # Taken from Firefight's library as it was, when a skill is copied or a copy takes a newer library version.
  AUTHOR_FIREFIGHT = "firefight".freeze
  AUTHOR_KINDS = [ AUTHOR_PERSON, AUTHOR_HALON, AUTHOR_FIREFIGHT ].freeze

  WHEN_LIMIT = 500
  STEPS_LIMIT = 20_000
  TOOLS_LIMIT = 40
  REASON_LIMIT = 1000
  CONTENT_KEYS = %w[when tools steps references signals].freeze

  # What a skill says reaches every prompt that loads it, like the handbook, so it is kept like the handbook.
  encrypts :used_when, :steps

  belongs_to :custom_skill, class_name: "Chat::CustomSkill", inverse_of: :versions
  belongs_to :author, class_name: "WorkspaceMembership", optional: true
  belongs_to :parent_version, class_name: "Chat::CustomSkill::Version", optional: true
  belongs_to :conversation, optional: true
  belongs_to :decided_by, class_name: "WorkspaceMembership", optional: true

  normalizes :used_when, with: ->(value) { value.to_s.squish }
  normalizes :steps, with: ->(value) { value.to_s.gsub("\r\n", "\n").strip }
  normalizes :tools, :references, :signals, with: ->(values) { Array(values).map { |value| value.to_s.strip }.compact_blank.uniq }, apply_to_nil: true
  normalizes :reason, with: ->(value) { value.to_s.squish.presence }

  validates :number, presence: true, uniqueness: { scope: :custom_skill_id }
  validates :status, inclusion: { in: STATUSES }
  validates :author_kind, inclusion: { in: AUTHOR_KINDS }
  validates :used_when, presence: { message: "should say when Halon uses it" }, length: { maximum: WHEN_LIMIT }
  validates :steps, presence: { message: "should say what Halon does" }, length: { maximum: STEPS_LIMIT }
  validates :tools, length: { maximum: TOOLS_LIMIT, message: "can name at most #{TOOLS_LIMIT}" }
  validates :reason, length: { maximum: REASON_LIMIT }
  validates :reason, presence: { message: "should say why Halon proposes it" }, if: :by_halon?
  validate :holds_no_secret
  validate :signals_known
  validate :references_known, on: :create
  validate :content_unchanged, on: :update

  scope :proposed, -> { where(status: STATUS_PROPOSED) }
  scope :newest_first, -> { order(number: :desc) }

  def live? = status == STATUS_LIVE
  def proposed? = status == STATUS_PROPOSED
  def by_halon? = author_kind == AUTHOR_HALON

  def content = { "when" => used_when, "tools" => tools, "steps" => steps, "references" => references, "signals" => signals }

  def self.content_attributes(content)
    content = content.to_h.stringify_keys
    { used_when: content["when"], tools: content["tools"], steps: content["steps"], references: content["references"], signals: content["signals"] }
  end

  # Decisions on what Halon proposed in a chat that it has not been told yet, claimed once each so two turns never both
  # tell the same one.
  def self.untold_for!(conversation)
    where(conversation: conversation, author_kind: AUTHOR_HALON).where.not(decided_at: nil).where(told_at: nil)
      .includes(:custom_skill, :decided_by).to_a
      .select { |version| where(id: version.id, told_at: nil).update_all(told_at: Time.current) == 1 }
  end

  # What Halon is told once a person decided on its proposal.
  def outcome_note
    who = decided_by&.actor_display_name || "Someone"
    name = custom_skill.name
    case status
    when STATUS_DISMISSED then "#{who} dismissed your proposed skill #{name}, so it is unchanged."
    when STATUS_EDITED then "#{who} edited your proposed skill #{name} before accepting it. Load it again with use_skill before you follow it."
    else "#{who} accepted your proposed skill #{name}. use_skill loads it as you wrote it."
    end
  end

  # Who wrote it, as a sentence names them.
  def author_words
    return "Halon" if by_halon?
    return "Firefight" if author_kind == AUTHOR_FIREFIGHT

    author&.actor_display_name || "Someone"
  end

  private

  def holds_no_secret
    text = [ used_when, steps ].join("\n")
    found = Chat::SecretFree::SECRET_PATTERNS.keys.find { |name| text.match?(Chat::SecretFree::SECRET_PATTERNS[name]) }
    errors.add(:base, "It looks like it holds a secret (#{found.to_s.humanize(capitalize: false)}), so it is not saved. Name the connection that holds it instead.") if found
  end

  def signals_known
    unknown = signals - Chat::Skill::SIGNALS
    errors.add(:signals, "#{unknown.to_sentence} #{unknown.one? ? 'is not a signal' : 'are not signals'} a skill can read") if unknown.any?
  end

  # A guide is a page of the provider's documentation, so only a copy of a provider's skill can list one, and only a page
  # its provider's documentation can hold.
  def references_known
    return if references.blank? || custom_skill.nil?
    return errors.add(:references, "can only be listed by a copy of a provider's skill") if custom_skill.source == Chat::Skill::SOURCE_WORKSPACE

    known = Array(custom_skill.library_base.to_h["references"]) | Chat::Skill.references_of(custom_skill.source)
    unknown = references - known
    errors.add(:references, "#{unknown.to_sentence} #{unknown.one? ? 'is not a page' : 'are not pages'} of the provider's documentation") if unknown.any?
  end

  def content_unchanged
    return unless %w[used_when tools steps references signals].any? { |column| attribute_changed?(column) }

    errors.add(:base, "A version never changes once written, so write a new one instead.")
  end
end
