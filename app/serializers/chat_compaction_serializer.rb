# A time Halon made room in its model's window, as the chat and a run's story show it. Never the note it wrote itself.
class ChatCompactionSerializer < BaseSerializer
  object_as :compaction

  type :string
  def key = compaction.step_key

  type :string
  def title = Chat::Compaction::SHOWN_AS

  type :string
  def at = compaction.created_at.utc.iso8601(3)
end
