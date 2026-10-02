# One step of a fix, as the run page shows it.
class InvestigationRemediationStepSerializer < BaseSerializer
  object_as :step

  type :string
  def id = step.id

  type :number
  def position = step.position

  type "RemediationStepKind"
  def kind = step.kind

  type :string
  def description = step.description

  type :string, optional: true
  def repository = step.repository

  # The tool an action runs, as the workspace knows it, such as cloudflare.execute.
  type :string, optional: true
  def action = step.action_key

  type :string, optional: true
  def missing = step.missing

  type :string, optional: true
  def undo = step.undo

  type "number[]"
  def depends_on = step.depends_on

  type "RemediationStepStatus"
  def status = step.status

  # Whether Firefight runs it when the fix is applied, an action or a code change it can open, rather than a person.
  type :boolean
  def runs_itself = step.runs_itself?

  # What the tool said back, another system's words, rendered as text.
  type :string, optional: true
  def result = step.result

  type :string, optional: true
  def done_by = step.done_by&.display_name

  type :string, optional: true
  def mark_done_blocked_reason = step.mark_done_blocked_reason

  # The ledger row written before the call, whose decision is what let it run.
  type "{ decision: string, at: string } | null"
  def receipt
    step.invocation && { decision: step.invocation.decision, at: step.invocation.created_at.utc.iso8601 }
  end
end
