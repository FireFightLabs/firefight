module SolidWorkflow
  class RunStepJob < ActiveJob::Base
    queue_as { SolidWorkflow.queue_name }

    def perform(step_id)
      start_time = Time.current

      @step = SolidWorkflow::Step.find(step_id)
      @workflow = @step.workflow

      return if @step.succeeded? || @step.cancelled? || @step.running?
      return if @workflow.cancelled?

      current_updated_at = @step.updated_at
      rows_updated = SolidWorkflow::Step.where(
        id: @step.id,
        status: :pending,
        updated_at: current_updated_at
      ).update_all(
        status: :running,
        attempts: @step.attempts + 1,
        started_at: Time.current,
        updated_at: Time.current
      )

      return if rows_updated == 0

      @step.reload
      @workflow.reload

      if @workflow.cancelled?
        @step.update!(status: :cancelled, completed_at: Time.current)
        return
      end

      @workflow.record_event(SolidWorkflow::Events::Step::STARTED, step: @step)

      Rails.logger.info({
        event: "workflow.step.started",
        workflow_id: @workflow.id,
        workflow_class: @workflow.workflow_class,
        step_id: @step.id,
        step_name: @step.name,
        attempt: @step.attempts,
        max_attempts: @step.max_attempts,
        subject_type: @workflow.subject_type,
        subject_id: @workflow.subject_id
      })

      @step.execute!

      duration = Time.current - start_time
      Rails.logger.info({
        event: "workflow.step.succeeded",
        workflow_id: @workflow.id,
        workflow_class: @workflow.workflow_class,
        step_id: @step.id,
        step_name: @step.name,
        duration_seconds: duration.round(2),
        total_attempts: @step.attempts
      })

    rescue StandardError => e
      Rails.logger.error({
        event: "workflow.step.failed",
        workflow_id: @workflow.id,
        workflow_class: @workflow.workflow_class,
        step_id: @step.id,
        step_name: @step.name,
        error_class: e.class.name,
        error_message: e.message,
        attempt: @step.attempts + 1,
        max_attempts: @step.max_attempts,
        will_retry: @step.should_retry?
      })

      @step.mark_failed!(e)
    ensure
      @workflow.enqueue_next_steps_later if @workflow
    end
  end
end
