class Workflows::RunStepJob < ApplicationJob
  queue_as :workflows

  def perform(step_id)
    @step = WorkflowStep.lock.find(step_id)
    @workflow = @step.workflow.reload

    # Log step start
    Rails.logger.info(
      :workflow_step_started,
      workflow_id: @workflow.id,
      workflow_class: @workflow.workflow_class,
      step_id: @step.id,
      step_name: @step.name,
      attempt: @step.attempts + 1,
      max_attempts: @step.max_attempts,
      subject_type: @workflow.subject_type,
      subject_id: @workflow.subject_id
    )

    start_time = Time.current

    ActiveRecord::Base.transaction do
      @step.execute!
    end

    # Log step success
    duration = Time.current - start_time
    Rails.logger.info(
      :workflow_step_succeeded,
      workflow_id: @workflow.id,
      workflow_class: @workflow.workflow_class,
      step_id: @step.id,
      step_name: @step.name,
      duration_seconds: duration.round(2),
      total_attempts: @step.attempts
    )

  rescue StandardError => e
    # Log step failure with error details
    Rails.logger.error(
      :workflow_step_failed,
      workflow_id: @workflow.id,
      workflow_class: @workflow.workflow_class,
      step_id: @step.id,
      step_name: @step.name,
      error_class: e.class.name,
      error_message: e.message,
      attempt: @step.attempts + 1,
      max_attempts: @step.max_attempts,
      will_retry: @step.should_retry?,
      backtrace: e.backtrace&.first(5)
    )

    @step.mark_failed!(e)
  ensure
    # Always trigger orchestration
    @workflow.enqueue_next_steps_later if @workflow
  end
end
