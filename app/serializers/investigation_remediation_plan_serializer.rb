# How to fix what a run found.
class InvestigationRemediationPlanSerializer < BaseSerializer
  object_as :plan

  type :string
  def summary = plan.summary

  type :string, optional: true
  def verify = plan.verify

  type :string
  def id = plan.id

  type "RemediationPlanStatus"
  def status = plan.status

  # Whether anything in it runs through a connection, and nobody applied it yet, which is when Apply fix shows.
  type :boolean
  def appliable = plan.apply_offered?

  # Why nobody can apply it now. Whether the viewer may run each tool is checked when they click.
  type :string, optional: true
  def apply_blocked_reason = plan.apply_blocked_reason

  type :string, optional: true
  def applied_by = plan.approved_by&.display_name

  type :string, optional: true
  def applied_at = plan.approved_at&.utc&.iso8601

  # Why it cannot be undone now, when it cannot. Undo fix shows only on a fix that was applied.
  type :string, optional: true
  def undo_blocked_reason = plan.undo_blocked_reason

  type :boolean
  def writing_undo = plan.writing_undo?

  # Why it cannot be cancelled now, when it cannot. Cancel shows only while it is being applied.
  type :string, optional: true
  def cancel_blocked_reason = plan.cancel_blocked_reason

  type :string, optional: true
  def cancelled_by = plan.cancelled_by&.display_name

  type :string, optional: true
  def cancelled_at = plan.cancelled_at&.utc&.iso8601

  # An undo reads as one, applied with its own wording.
  type :boolean
  def is_undo = plan.undo?

  type :string, optional: true
  def undo_error = plan.undo_error

  has_many :steps, serializer: InvestigationRemediationStepSerializer do
    plan.steps.includes(:invocation, :done_by)
  end

  # Whether a step is running or about to, which is when the run page keeps itself current.
  type :boolean
  def moving = plan.moving?
end
