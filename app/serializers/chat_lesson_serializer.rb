# A lesson an incident taught as the Lessons tab shows it to options[:member]: what it says, where it stands for pull
# request reviews, who decided, and why that member cannot approve, edit or turn it down when they cannot.
class ChatLessonSerializer < BaseSerializer
  object_as :lesson

  type :string
  def id = lesson.id

  type :string
  def text = lesson.text

  type "LessonStatus"
  def status = lesson.lesson_status

  type "ChatMemoryState"
  def state = lesson.state

  type :boolean
  def strict = lesson.strict

  type :string, optional: true
  def about = lesson.about

  # Where it came from, such as "INC-052 Checkout failing" or "PR #412 in acme/checkout".
  type :string
  def origin = lesson.lesson_origin_title

  # The incident's page in the dashboard, or the pull request on its code host, which opens in a new tab.
  type :string, optional: true
  def origin_url = lesson.lesson_origin_url

  type :boolean
  def origin_elsewhere = lesson.from_pull_request?

  type :string, optional: true
  def approved_by = (lesson.approved_by&.display_name if lesson.approved_lesson?)

  type :string, optional: true
  def approved_at = (lesson.approved_at&.utc&.iso8601 if lesson.approved_lesson?)

  type :string, optional: true
  def turned_down_by = (lesson.rejected_by&.display_name if lesson.lesson_status == Chat::Memory::Lesson::STATUS_TURNED_DOWN)

  # Why it stands where it does, such as why it was disputed or turned down.
  type :string, optional: true
  def reason = lesson.state_reason

  type :string
  def created_at = lesson.created_at.utc.iso8601

  type :string, optional: true
  def approve_blocked_reason = lesson.approve_blocked_reason(options[:member])

  type :string, optional: true
  def edit_blocked_reason = lesson.edit_lesson_blocked_reason(options[:member])

  type :string, optional: true
  def turn_down_blocked_reason = lesson.turn_down_blocked_reason(options[:member])
end
