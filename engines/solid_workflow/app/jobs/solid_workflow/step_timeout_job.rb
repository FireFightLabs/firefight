module SolidWorkflow
  # Ends an attempt that ran past its step's time limit, as a failure that retries while attempts remain. Only the
  # attempt it was booked for moves, so a retry already running under a later deadline is left alone. The job still
  # running the attempt finds the step moved on and drops what it was doing.
  class StepTimeoutJob < ActiveJob::Base
    queue_as { SolidWorkflow.queue_name }

    def perform(step_id)
      step = SolidWorkflow::Step.find_by(id: step_id)
      return unless step&.running? && step.timeout_at && step.timeout_at <= Time.current

      self.class.time_out!(step)
    end

    def self.time_out!(step)
      error = SolidWorkflow::StepTimedOut.new("Step ran past its time limit of #{step.timeout_seconds} seconds")
      return unless step.mark_failed!(error, timeout_at: step.timeout_at)

      step.workflow.record_event(SolidWorkflow::Events::Step::TIMED_OUT, step: step, timeout_seconds: step.timeout_seconds)
      step.workflow.enqueue_next_steps_later
    end
  end
end
