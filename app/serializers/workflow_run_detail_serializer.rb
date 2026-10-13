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

  has_many :steps, serializer: WorkflowRunStepSerializer do
    run.steps
  end
end
