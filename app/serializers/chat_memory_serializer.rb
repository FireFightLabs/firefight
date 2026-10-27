# A memory as the Memory page shows it: what it says, what it is about, where it came from, who decided on it, how it
# stands, what Halon's nightly check found, and its history.
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
    when CodeAgentSession then "#{memory.source.lesson_origin} in #{memory.source.repository}"
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

  # Halon's nightly check made the last decision, with no person behind it.
  type :boolean
  def decided_by_halon = memory.decided_by_halon

  # Who stands behind a memory in use: a person, a postmortem, Halon's check, or nobody yet. Nil when it is not in use.
  type "ChatMemoryStanding", optional: true
  def standing = memory.standing

  # When Halon last tried to check it, whatever came of it.
  type :string, optional: true
  def checked_at = memory.checked_at&.utc&.iso8601

  type "ChatMemoryCheckOutcome", optional: true
  def check_outcome = memory.check_outcome

  # What Halon read in production the last time it showed it right, and when.
  type :string, optional: true
  def verified_evidence = verified&.detail

  type :string, optional: true
  def verified_at = verified&.created_at&.utc&.iso8601

  # The nightly run that last showed it right, which opens on its own page, when the reader may open it (options[:runs]).
  type :string, optional: true
  def verified_investigation_id = verified&.investigation_id&.then { |id| id if options.fetch(:runs, Set.new).include?(id) }

  # Everything that happened to it, oldest first.
  has_many :events, serializer: ChatMemoryEventSerializer do
    memory.events.to_a
  end

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
  def in_use = memory.in_use?

  # Waiting on a person, which the page counts on its tab: a contradiction Halon could not settle, or evidence Halon
  # found against what a person decided.
  type :boolean
  def awaiting_decision = memory.awaiting_decision?

  type :string, optional: true
  def confirm_blocked_reason = memory.confirm_blocked_reason

  type :string, optional: true
  def reject_blocked_reason = memory.reject_blocked_reason

  # What deleting it means, said before and after.
  type :string
  def delete_consequence = memory.delete_consequence

  private

  def verified = memo.fetch(:verified) { memory.last_verified }
end
