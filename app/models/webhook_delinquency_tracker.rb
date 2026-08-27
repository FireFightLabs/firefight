class WebhookDelinquencyTracker < ApplicationRecord
  DELINQUENCY_THRESHOLD = 10
  DELINQUENCY_DURATION = 1.hour

  belongs_to :webhook

  DEACTIVATION_REASON = "delinquency_threshold"

  # Returns true when this delivery tipped the webhook into deactivation, so
  # the caller can tell someone.
  def record_delivery(delivery)
    if delivery.succeeded?
      reset
      false
    else
      mark_first_failure_time if consecutive_failures_count.zero?
      increment!(:consecutive_failures_count, touch: true)

      delinquent? && auto_deactivate!
    end
  end

  private

  def auto_deactivate!
    return false unless webhook.active?

    webhook.deactivate!
    true
  end

  def reset
    update_columns(consecutive_failures_count: 0, first_failure_at: nil)
  end

  def mark_first_failure_time
    update_columns(first_failure_at: Time.current)
  end

  def delinquent?
    too_many_consecutive_failures? && failing_for_too_long?
  end

  def too_many_consecutive_failures?
    consecutive_failures_count >= DELINQUENCY_THRESHOLD
  end

  def failing_for_too_long?
    first_failure_at.present? && first_failure_at.before?(DELINQUENCY_DURATION.ago)
  end
end
