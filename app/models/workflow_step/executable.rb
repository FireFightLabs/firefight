module WorkflowStep::Executable
  extend ActiveSupport::Concern

  def execute!
    return if workflow.cancelled?
    return if succeeded? || cancelled?

    # Record start
    workflow.record_event(WorkflowEvents::Step::STARTED, step: self)

    # Update to running
    update!(
      status: :running,
      attempts: attempts + 1,
      started_at: Time.current
    )

    # Execute the step
    runner = workflow.workflow_klass.new
    output = runner.run_step(
      name,
      workflow: workflow,
      step: self,
      input: input
    )

    # Mark as succeeded
    update!(
      status: :succeeded,
      output: output || {},
      completed_at: Time.current
    )

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
