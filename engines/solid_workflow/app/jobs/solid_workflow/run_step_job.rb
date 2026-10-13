module SolidWorkflow
  class RunStepJob < ActiveJob::Base
    queue_as { SolidWorkflow.queue_name }

    def perform(step_id)
      start_time = Time.current

      @step = SolidWorkflow::Step.find(step_id)
      @workflow = @step.workflow

      return if @step.succeeded? || @step.cancelled?
      return if @workflow.cancelled?
      return unless @workflow.runnable?

      resuming = @step.running?
      return unless resuming ? resume_step : claim_step

      @step.reload
      @workflow.reload
      SolidWorkflow::StepTimeoutJob.set(wait_until: @step.timeout_at).perform_later(@step.id) if @step.timeout_at

      if @workflow.cancelled?
        @step.update!(status: :cancelled, completed_at: Time.current)
        return
      end

      @workflow.record_event(resuming ? SolidWorkflow::Events::Step::RESUMED : SolidWorkflow::Events::Step::STARTED, step: @step)

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
        will_retry: @step.should_retry?(e)
      })

      @step.mark_failed!(e, claimed_by: job_id)
    ensure
      @workflow.enqueue_next_steps_later if @workflow
    end

    private

    # The job that runs a step is written on it, so only that job can take it up again.
    def claim_step
      now = Time.current
      SolidWorkflow::Step.where(id: @step.id, status: :pending, updated_at: @step.updated_at).update_all(
        status: :running, claimed_by: job_id, attempts: @step.attempts + 1, started_at: now, updated_at: now,
        first_started_at: Arel.sql(SolidWorkflow::Step.sanitize_sql_array([ "COALESCE(first_started_at, ?)", now ])),
        timeout_at: attempt_deadline(now)
      ) > 0
    end

    # A running step held by this same job was cut off by a stopped worker, since Solid Queue hands a job out again only
    # once its worker is gone. It runs again at once, as another attempt, rather than waiting for the sweeper. Any other
    # job finds the step held and leaves it.
    def resume_step
      now = Time.current
      SolidWorkflow::Step.where(id: @step.id, status: :running, claimed_by: job_id).update_all(
        attempts: @step.attempts + 1, updated_at: now, timeout_at: attempt_deadline(now)
      ) > 0
    end

    # A step that waits measures its time limit from when it first started, so only other steps get a deadline per attempt.
    def attempt_deadline(now)
      return unless @step.timeout_seconds
      return if SolidWorkflow::Definition::WAITING_KINDS.include?(@step.kind)

      now + @step.timeout_seconds.seconds
    end
  end
end
