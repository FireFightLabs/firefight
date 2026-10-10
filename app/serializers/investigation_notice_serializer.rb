# A problem Halon raised on its own, as the Monitoring page lists it.
class InvestigationNoticeSerializer < BaseSerializer
  object_as :notice

  type :string
  def id = notice.id

  attributes(
    signal: { type: :string },
    topic: { type: :string },
    summary: { type: :string },
    severity: { type: :string },
    times_said: { type: :number }
  )

  type :string
  def signal_label = Investigation::Notice::SIGNAL_LABELS.fetch(notice.signal)

  type :string
  def severity_label = Investigation::Notice::SEVERITY_LABELS.fetch(notice.severity)

  type :string, optional: true
  def due_on = notice.due_on&.iso8601

  type :string, optional: true
  def resource_name = notice.resource&.name

  type :string, optional: true
  def check_name = notice.check&.name

  type :string, optional: true
  def last_said_at = notice.last_said_at&.iso8601

  type :string
  def last_seen_at = notice.last_seen_at.iso8601

  # Why it is still waiting to be said, or why it was said only on its run's page.
  type :string, optional: true
  def unsaid_reason = notice.unsaid_reason

  type :string, optional: true
  def investigation_id = notice.investigation_id
end
