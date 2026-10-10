# A check a run handed to a helper, which its story draws as a group of the steps the helper took, with what it reported
# or why it has no report.
class InvestigationHelperSerializer < BaseSerializer
  object_as :helper

  type :string
  def id = helper.id

  # The run_helpers call it came from. Helpers from one call are drawn together.
  type :string
  def tool_call_id = helper.tool_call_id

  type :string
  def title = helper.title

  type :string
  def brief = helper.brief

  type Chat::Helper::STATUSES.map(&:inspect).join(" | ")
  def status = helper.status

  type :string, optional: true
  def report = (helper.report if helper.reported?)

  type :string, optional: true
  def ended_because = helper.ended_because

  type :string
  def started_at = helper.started_at.utc.iso8601
end
