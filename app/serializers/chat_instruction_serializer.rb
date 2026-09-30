# One place's instructions with their earlier wordings, as the Memory page shows it. object is [note, history].
class ChatInstructionSerializer < BaseSerializer
  object_as :pair

  type :string
  def id = pair.first.id

  type :string
  def text = pair.first.text

  type :string
  def label = pair.first.label

  type :string, optional: true
  def scope = Chat::Memory.subject_key(pair.first.scope)

  type :string, optional: true
  def added_by = pair.first.added_by&.display_name

  type :string
  def updated_at = pair.first.created_at.utc.iso8601

  # Earlier wordings, newest first, each as [id, when, who, text].
  type "string[][]"
  def history = pair.last.map { |note| [ note.id, note.created_at.utc.iso8601, note.added_by&.display_name.to_s, note.text ] }
end
