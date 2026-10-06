# A memory as the Memory page shows it: what it says, what it is about, where it came from, and who decided on it.
class ChatMemorySerializer < BaseSerializer
  object_as :memory

  type :string
  def id = memory.id

  type :string
  def text = memory.text

  type "ChatMemoryState"
  def state = memory.state

  type :string, optional: true
  def about = memory.about

  # What it is about is gone from the map.
  type :boolean
  def about_removed = memory.about_removed?

  type :string, optional: true
  def subject = Chat::Memory.subject_key(memory.subject)

  # Where it came from, in words, such as INC-042, a chat or the person who wrote it on this page.
  type :string
  def source_label
    case memory.source
    when Incident then "#{memory.source.identifier} #{memory.source.name}"
    when Investigation then "An investigation"
    when Conversation then "A chat"
    when WorkspaceMembership then "Written here"
    else "Unknown"
    end
  end

  type :string, optional: true
  def source_incident_id = (memory.source_id if memory.source.is_a?(Incident))

  type :string, optional: true
  def added_by = memory.added_by&.display_name

  type :string, optional: true
  def confirmed_by = memory.confirmed_by&.display_name

  # A completed postmortem made the last decision, whoever completed it.
  type :boolean
  def decided_by_postmortem = memory.decided_by_postmortem_id.present?

  type :string, optional: true
  def confirmed_at = memory.confirmed_at&.utc&.iso8601

  type :string, optional: true
  def rejected_by = memory.rejected_by&.display_name

  type :string, optional: true
  def reason = memory.state_reason

  type :string
  def created_at = memory.created_at.utc.iso8601

  type :string, optional: true
  def last_used_at = memory.last_used_at&.utc&.iso8601

  type :number
  def use_count = memory.use_count

  type :boolean
  def in_use = Chat::Memory::USED_STATES.include?(memory.state)

  type :string, optional: true
  def confirm_blocked_reason = memory.confirm_blocked_reason

  type :string, optional: true
  def reject_blocked_reason = memory.reject_blocked_reason

  # What deleting it means, said before and after.
  type :string
  def delete_consequence = memory.delete_consequence
end
