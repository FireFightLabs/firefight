require "test_helper"

class WebhookDelinquencyTrackerTest < ActiveSupport::TestCase
  setup do
    @webhook = webhooks(:active_webhook)
    @tracker = webhook_delinquency_trackers(:active_webhook_tracker)
  end

  test "resets on successful delivery" do
    @tracker.update_columns(consecutive_failures_count: 5, first_failure_at: 2.hours.ago)

    delivery = webhook_deliveries(:completed_delivery)
    @tracker.record_delivery(delivery)

    assert_equal 0, @tracker.consecutive_failures_count
    assert_nil @tracker.first_failure_at
  end

  test "increments consecutive failures on failed delivery" do
    delivery = webhook_deliveries(:errored_delivery)
    @tracker.record_delivery(delivery)

    assert_equal 1, @tracker.consecutive_failures_count
    assert_not_nil @tracker.first_failure_at
  end

  test "sets first_failure_at only on first failure" do
    delivery = webhook_deliveries(:errored_delivery)
    @tracker.record_delivery(delivery)
    first_failure = @tracker.first_failure_at

    @tracker.record_delivery(delivery)
    assert_equal first_failure.to_i, @tracker.reload.first_failure_at.to_i
  end

  test "deactivates webhook after threshold consecutive failures over duration" do
    @tracker.update_columns(
      consecutive_failures_count: WebhookDelinquencyTracker::DELINQUENCY_THRESHOLD - 1,
      first_failure_at: 2.hours.ago
    )

    delivery = webhook_deliveries(:errored_delivery)

    assert @tracker.record_delivery(delivery)
    assert_not @webhook.reload.active?
  end

  test "reports nothing to tell when the webhook is already inactive" do
    @webhook.deactivate!
    @tracker.update_columns(
      consecutive_failures_count: WebhookDelinquencyTracker::DELINQUENCY_THRESHOLD - 1,
      first_failure_at: 2.hours.ago
    )

    delivery = webhook_deliveries(:errored_delivery)

    assert_not @tracker.record_delivery(delivery)
  end

  test "does not deactivate webhook if failures are recent" do
    @tracker.update_columns(
      consecutive_failures_count: WebhookDelinquencyTracker::DELINQUENCY_THRESHOLD - 1,
      first_failure_at: 30.minutes.ago
    )

    delivery = webhook_deliveries(:errored_delivery)
    @tracker.record_delivery(delivery)

    assert @webhook.reload.active?
  end

  test "does not deactivate webhook if below failure threshold" do
    @tracker.update_columns(
      consecutive_failures_count: 3,
      first_failure_at: 2.hours.ago
    )

    delivery = webhook_deliveries(:errored_delivery)
    @tracker.record_delivery(delivery)

    assert @webhook.reload.active?
  end
end
