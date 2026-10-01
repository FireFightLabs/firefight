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
  def appliable = plan.appliable? && plan.status == Investigation::RemediationPlan::STATUS_PROPOSED

  # Why nobody can apply it now. Whether the viewer may run each tool is checked when they click.
  type :string, optional: true
  def apply_blocked_reason = plan.apply_blocked_reason

  type :string, optional: true
  def applied_by = plan.approved_by&.display_name

  type :string, optional: true
  def applied_at = plan.approved_at&.utc&.iso8601

  has_many :steps, serializer: InvestigationRemediationStepSerializer do
    plan.steps.includes(:invocation, :done_by)
  end

  # Whether a step is running or about to, which is when the run page keeps itself current.
  type :boolean
  def moving = plan.moving?
end
