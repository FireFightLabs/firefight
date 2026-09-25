# A Halon run as the operator console lists it and heads its trace.
class OperatorHalonRunSerializer < BaseSerializer
  object_as :run

  ENDING_UNION = Operator::HalonRuns::ENDINGS.map(&:inspect).join(" | ")

  type :string
  def id = run.id

  # An incident is named by its identifier and name, a question asked before one by the question.
  type :string
  def label
    incident = run.incident
    incident ? "#{incident.identifier} #{incident.name}" : run.question.to_s
  end

  type :string, optional: true
  def incident_id = run.incident_id

  type :string, optional: true
  def conversation_id = run.conversation_id

  type :string
  def workspace_name = run.workspace.name

  type ENDING_UNION
  def ending = Operator::HalonRuns.ending(run.status, run.error_summary)

  type :string
  def status = run.status

  # The words the thread was told, and the cause behind them, which only operators see.
  type :string, optional: true
  def stopped_because = run.stopped_because

  type :string, optional: true
  def error_summary = run.error_summary

  type :string
  def trigger_source = run.trigger_source

  type :boolean
  def rehearsal = run.rehearsal

  type :number
  def turns = run.turns_used

  type :number
  def max_turns = run.max_turns

  type :number
  def spent_micros = run.spent_micros

  type :number
  def max_spend_micros = run.max_spend_cents * FirefightAi::AgentLoop::MICROS_PER_CENT

  type :number, optional: true
  def seconds = run.duration_seconds

  type :boolean
  def not_posted = Operator::HalonRuns.not_posted?(run)

  type :string
  def created_at = run.created_at.utc.iso8601

  type :string, optional: true
  def completed_at = run.completed_at&.utc&.iso8601
end
