# One message in an incident's channel that asked people to decide on memories. It keeps the memories it first showed,
# so redrawing it after a decision shows those and nothing learned since.
class Chat::MemoryPost < ApplicationRecord
  self.table_name = "chat_memory_posts"

  # What the incident taught when it ended, or when an answer was marked wrong after.
  KIND_INCIDENT = "incident".freeze
  KIND_POSTMORTEM = "postmortem".freeze
  # A chat or a run working on the incident learned a fact, or disputed one.
  KIND_LEARNED = "learned".freeze
  KIND_DISPUTED = "disputed".freeze
  KINDS = [ KIND_INCIDENT, KIND_POSTMORTEM, KIND_LEARNED, KIND_DISPUTED ].freeze

  belongs_to :workspace
  belongs_to :incident

  validates :kind, inclusion: { in: KINDS }

  # The memories it shows, in the order first shown. One deleted since is left out.
  def memories
    found = Chat::Memory.where(workspace_id: workspace_id, id: memory_ids).includes(:subject, :confirmed_by, :rejected_by, :replaced_by).index_by(&:id)
    memory_ids.filter_map { |id| found[id] }
  end

  def shows?(memory) = memory_ids.include?(memory.id)

  def posted!(message_id) = update!(message_id: message_id)
end
