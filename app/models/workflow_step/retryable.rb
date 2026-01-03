module WorkflowStep::Retryable
  extend ActiveSupport::Concern

  # Backoff strategy constants
  BACKOFF_EXPONENTIAL = "exponential"
  BACKOFF_LINEAR = "linear"
  BACKOFF_FIXED = "fixed"

  def should_retry?
    attempts < max_attempts
  end

  def schedule_retry!
    delay = calculate_backoff

    update!(
      status: :pending,
      run_at: Time.current + delay
    )

    workflow.record_event(WorkflowEvents::Step::RETRY_SCHEDULED, step: self, delay: delay, attempt: attempts)
  end

  def retry_now!
    transaction do
      update!(
        status: :pending,
        attempts: 0,
        last_error: nil,
        run_at: nil
      )

      workflow.record_event(WorkflowEvents::Step::MANUAL_RETRY, step: self)
    end

    workflow.enqueue_next_steps
  end

  def skip!(reason:)
    transaction do
      update!(
        status: :skipped,
        skip_reason: reason,
        completed_at: Time.current
      )

      workflow.record_event(WorkflowEvents::Step::MANUAL_SKIP, step: self, reason: reason)
    end

    workflow.enqueue_next_steps
  end

  private

  def calculate_backoff
    strategy = retry_config&.dig("backoff") || BACKOFF_EXPONENTIAL

    case strategy
    when BACKOFF_EXPONENTIAL
      [ 2**attempts, 300 ].min.seconds
    when BACKOFF_LINEAR
      [ attempts * 30, 300 ].min.seconds
    when BACKOFF_FIXED
      (retry_config["backoff_seconds"] || 60).seconds
    else
      60.seconds
    end
  end
end
