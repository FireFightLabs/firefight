# One run as its own page shows it: what started it and with what, who it acted as, each step with what it took in,
# gave back and why it failed, the calls it made as the activity log keeps them, what it cost, and what can be done
# with it now.
class WorkflowRunSerializer < WorkflowRunRowSerializer
  type :number
  def version_number = run.version.number

  type :string, optional: true
  def acted_as = run.test? ? run.started_by&.display_name : run.agent&.name

  type "Record<string, unknown>"
  def inputs = run.inputs.to_h

  type "Record<string, unknown> | null"
  def outputs = run.outputs

  type :string, optional: true
  def started_at = run.started_at&.iso8601

  type :string, optional: true
  def details_pruned_at = run.details_pruned_at&.iso8601

  type :number
  def ai_spent_cents = run.ai_spent_cents

  type :number, optional: true
  def cost_cap_cents = run.workflow.cost_cap_cents

  # Each step as it ran, in order, a for each's items told apart by their place.
  type "{ key: string; name: string; kind: string; kindLabel: string; status: string; route?: string; iteration: string; input?: unknown; output?: unknown; error?: string; attempts: number; startedAt?: string; finishedAt?: string; simulated: boolean; real: boolean; undo?: string; waitingOn?: string }[]"
  def steps
    specs = run.version.steps_by_id
    order = specs.keys
    approvals = waiting_approvals
    run.steps.sort_by { |step| [ order.index(step.step_key) || order.size, step.iteration ] }.map do |step|
      spec = specs[step.step_key].to_h
      kind = DefinedWorkflow::Steps.for(step.kind)
      {
        key: step.step_key, name: step.name.to_s, kind: step.kind.to_s, kindLabel: kind&.label || step.kind.to_s.humanize, status: step.status,
        route: step.route, iteration: step.iteration, input: step.input, output: step.output, error: step.error, attempts: step.attempts,
        startedAt: step.started_at&.iso8601, finishedAt: step.finished_at&.iso8601,
        simulated: step.output.to_h[DefinedWorkflow::Steps::Base::OUTPUT_SIMULATED] == true, real: run.real_step_keys.include?(step.step_key),
        undo: spec.dig("config", DefinedWorkflow::Steps::Base::KEY_UNDO).presence,
        waitingOn: (approvals[step.step_key] if step.status == Workflow::Run::Step::STATUS_WAITING)
      }.compact
    end
  end

  # Every call the run's steps made, as the activity log keeps it.
  type "{ id: string; actionKey: string; connection?: string; decision: string; outcome?: string; summary?: string; at: string }[]"
  def calls
    Ability::Invocation.with_connection_names(run.invocations.order(:created_at)).map do |call|
      { id: call.id, actionKey: call.action_key, connection: call.connection_name, decision: call.decision, outcome: call.outcome,
        summary: call.error_summary, at: call.created_at.iso8601 }.compact
    end
  end

  # The notices its steps raised.
  type "{ id: string; topic: string; summary: string; said: boolean }[]"
  def notices = run.notices.map { |notice| { id: notice.id, topic: notice.topic, summary: notice.summary, said: notice.last_said_at.present? } }

  type :string, optional: true
  def cancel_blocked_reason = run.cancel_blocked_reason

  type :string, optional: true
  def pin_blocked_reason = run.pin_blocked_reason

  private

  # What a waiting step waits on, by its step: the approval its held call asked for.
  def waiting_approvals
    Ability::Approval.where(workflow_run_id: run.id, status: Ability::Approval::STATUS_PENDING).each_with_object({}) do |approval, found|
      key = approval.resume_payload.to_h["step_key"]
      named = [ approval.action_key, (" on #{approval.connection_name}" if approval.connection_name) ].join
      found[key] = "Waiting for someone to approve #{named}." if key
    end
  end
end
