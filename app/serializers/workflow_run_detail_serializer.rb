# The run the canvas shows: everything its row says, what started it and with what, what it handed back, and every
# step it ran with what each did, the changes the tester made for real, and whether it can be stopped.
class WorkflowRunDetailSerializer < WorkflowRunRowSerializer
  type "Record<string, unknown>"
  def inputs
    run.inputs
  end

  type "Record<string, unknown>", optional: true
  def outputs
    run.outputs
  end

  # Who started it, in place of what started it, for a run a person or Halon for a person asked for, which holds
  # nothing of what started it.
  type :string, optional: true
  def started_line
    return unless run.asked_for?

    name = run.started_by&.display_name
    return "Started by hand by #{name || 'someone'}." if run.started_by_kind == Workflow::Run::STARTED_BY_PERSON

    name ? "Started by Halon for #{name}." : "Started by Halon."
  end

  type "string[]"
  def real_step_keys
    run.real_step_keys
  end

  type :string, optional: true
  def rerun_of_id
    run.rerun_of_id
  end

  type :string, optional: true
  def cancel_blocked_reason
    run.cancel_blocked_reason
  end

  # What it spent, its model calls and its sandbox's time apart, both held to the workflow's spending ceiling.
  type :number
  def ai_spent_micros
    run.ai_spent_micros
  end

  type :number
  def sandbox_spent_micros
    run.sandbox_spent_micros
  end

  type :number, optional: true
  def cost_cap_cents
    run.workflow.cost_cap_cents
  end

  # Each step that skipped itself, with why.
  type "string[]"
  def notes
    run.steps.filter_map { |step| "#{step.name.presence || step.step_key}: #{step.note}" if step.note }
  end

  has_many :steps, serializer: WorkflowRunStepSerializer do
    run.steps
  end
end
