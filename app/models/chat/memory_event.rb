# One thing that happened to a memory, for its history on the Memory page: learned, confirmed, checked by Halon,
# disputed, corrected, rejected, merged, flagged outdated or expired. It says who did it (a person, Halon or a postmortem)
# and why, such as what Halon read in production. The detail can quote production or the memory itself, so it is
# encrypted like the memory.
class Chat::MemoryEvent < ApplicationRecord
  self.table_name = "chat_memory_events"

  KIND_LEARNED = "learned".freeze
  KIND_WRITTEN = "written".freeze
  KIND_CONFIRMED = "confirmed".freeze
  # Halon checked it against production and it held.
  KIND_VERIFIED = "verified".freeze
  # Halon tried and could not tell either way, or was stopped before it got to it.
  KIND_UNSETTLED = "unsettled".freeze
  # Halon found it wrong but tonight's limit on removals was reached, so it was left as it was.
  KIND_HELD = "held".freeze
  KIND_DISPUTED = "disputed".freeze
  KIND_CORRECTED = "corrected".freeze
  KIND_REJECTED = "rejected".freeze
  KIND_MERGED = "merged".freeze
  # Another memory saying the same thing was merged into this one.
  KIND_ABSORBED = "absorbed".freeze
  KIND_OUTDATED = "outdated".freeze
  KIND_CURRENT_AGAIN = "current_again".freeze
  KIND_EXPIRED = "expired".freeze
  KIND_REVIVED = "revived".freeze
  KINDS = [ KIND_LEARNED, KIND_WRITTEN, KIND_CONFIRMED, KIND_VERIFIED, KIND_UNSETTLED, KIND_HELD, KIND_DISPUTED, KIND_CORRECTED,
            KIND_REJECTED, KIND_MERGED, KIND_ABSORBED, KIND_OUTDATED, KIND_CURRENT_AGAIN, KIND_EXPIRED, KIND_REVIVED ].freeze

  ACTOR_PERSON = "person".freeze
  ACTOR_HALON = "halon".freeze
  ACTOR_POSTMORTEM = "postmortem".freeze
  ACTORS = [ ACTOR_PERSON, ACTOR_HALON, ACTOR_POSTMORTEM ].freeze

  encrypts :detail

  belongs_to :workspace
  belongs_to :memory, class_name: "Chat::Memory"
  belongs_to :member, class_name: "WorkspaceMembership", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :actor, inclusion: { in: ACTORS }, allow_nil: true

  scope :in_order, -> { order(:created_at) }

  # The same event for several memories at once, such as each one a sweep flagged outdated.
  def self.record_all!(memory_ids, workspace_id:, kind:, actor: nil, detail: nil, at: Time.current)
    return if memory_ids.empty?

    rows = memory_ids.map { |id| { workspace_id: workspace_id, memory_id: id, kind: kind, actor: actor, detail: detail, created_at: at } }
    # insert_all skips encryption, so each row is built through the model when it carries words.
    detail.nil? ? insert_all!(rows) : rows.each { |row| create!(row) }
  end

  # Who did it, in words, such as "Ana", "Halon" or "a postmortem".
  def by
    case actor
    when ACTOR_HALON then "Halon"
    when ACTOR_POSTMORTEM then "a postmortem"
    when ACTOR_PERSON then member&.display_name || "a person"
    end
  end
end
