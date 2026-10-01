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
end
