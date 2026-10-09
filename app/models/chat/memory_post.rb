# One place people were asked to decide on memories: a message in an incident's channel, a direct message reminding a
# person, or a card in a dashboard chat. It keeps the memories it first showed, so redrawing it after a decision shows
# those and nothing learned since.
class Chat::MemoryPost < ApplicationRecord
  self.table_name = "chat_memory_posts"

  # What the incident taught when it ended, or when an answer was marked wrong after.
  KIND_INCIDENT = "incident".freeze
  KIND_POSTMORTEM = "postmortem".freeze
  # A chat or a run working on the incident learned a fact, or disputed one.
  KIND_LEARNED = "learned".freeze
  KIND_DISPUTED = "disputed".freeze
  # Memories nobody confirmed for a while, to the person who taught them or for the team.
  KIND_REMINDER = "reminder".freeze
  KINDS = [ KIND_INCIDENT, KIND_POSTMORTEM, KIND_LEARNED, KIND_DISPUTED, KIND_REMINDER ].freeze

  # What a dispute raised in a chat said showed the memory wrong, kept as the person read it.
  encrypts :evidence

  belongs_to :workspace
  belongs_to :incident, optional: true
  # The dashboard chat the card sits in.
  belongs_to :conversation, optional: true
  # Whom a reminder went to by direct message. A reminder in an incident's channel has none.
  belongs_to :recipient, class_name: "WorkspaceMembership", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :channel_id, presence: true, unless: :conversation_id

  scope :reminders, -> { where(kind: KIND_REMINDER) }

  # The memories it shows, in the order first shown. One deleted since is left out.
  def memories
    found = Chat::Memory.where(workspace_id: workspace_id, id: memory_ids).includes(:subject, :confirmed_by, :rejected_by, :replaced_by).index_by(&:id)
    memory_ids.filter_map { |id| found[id] }
  end

  def posted!(message_id, channel_id: self.channel_id) = update!(message_id: message_id, channel_id: channel_id)

  # Where a decision was made, as its reason says, such as "Marked not right in INC-12".
  def place
    return incident.identifier if incident
    return "a chat" if conversation_id

    "a reminder"
  end
end
