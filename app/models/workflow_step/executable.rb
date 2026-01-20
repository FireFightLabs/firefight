module WorkflowStep::Executable
  extend ActiveSupport::Concern

  def execute!
    return if workflow.cancelled?
    return if succeeded? || cancelled?

    # Status transition to 'running' now handled by RunStepJob
    # This method assumes step is already in 'running' status

    # Reload to get latest input data populated by orchestrator
    reload

    # Execute the step
    runner = workflow.workflow_klass.new
    output = runner.run_step(
      name,
      workflow: workflow,
      step: self,
      input: input
    )

    # Atomic transition: running → succeeded with optimistic locking
    current_updated_at = updated_at
    rows_updated = WorkflowStep.where(
      id: id,
      status: :running,
      updated_at: current_updated_at
    ).update_all(
      status: :succeeded,
      output: output || {},
      completed_at: Time.current,
      updated_at: Time.current
    )

    # If update failed, step was cancelled/modified - reload and check
    if rows_updated == 0
      reload
      return if cancelled? # Cancelled during execution - exit gracefully
      raise "Step status changed unexpectedly during execution"
    end

    reload # Reload to get updated attributes
    workflow.record_event(WorkflowEvents::Step::SUCCEEDED, step: self)
  end

  def mark_failed!(error)
    update!(last_error: format_error(error))
    workflow.record_event(WorkflowEvents::Step::FAILED, step: self, error: error.message)

    if should_retry?
      schedule_retry!
    else
      update!(status: :failed, completed_at: Time.current)
    end
  end

  private

  def format_error(error)
    "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
  end
end
