require "test_helper"

class WebhookDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_events,
           :webhooks, :webhook_delinquency_trackers, :webhook_deliveries

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "belongs to webhook" do
    delivery = webhook_deliveries(:completed_delivery)
    assert_instance_of Webhook, delivery.webhook
    assert_equal webhooks(:active_webhook), delivery.webhook
  end

  test "belongs to incident_event" do
    delivery = webhook_deliveries(:completed_delivery)
    assert_instance_of IncidentEvent, delivery.incident_event
  end

  # ============================================================================
  # STATE
  # ============================================================================

  test "default state is pending" do
    delivery = WebhookDelivery.new
    assert_equal "pending", delivery.state
  end

  test "succeeded? returns true for completed delivery with 2xx response" do
    delivery = webhook_deliveries(:completed_delivery)
    assert delivery.succeeded?
  end

  test "succeeded? returns false for errored delivery" do
    delivery = webhook_deliveries(:errored_delivery)
    assert_not delivery.succeeded?
  end

  test "failed? returns true for errored delivery" do
    delivery = webhook_deliveries(:errored_delivery)
    assert delivery.failed?
  end

  test "failed? returns false for successful delivery" do
    delivery = webhook_deliveries(:completed_delivery)
    assert_not delivery.failed?
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "stale scope finds deliveries older than threshold" do
    old_delivery = webhook_deliveries(:completed_delivery)
    old_delivery.update_columns(created_at: 8.days.ago)

    assert_includes WebhookDelivery.stale, old_delivery
  end

  test "stale scope excludes recent deliveries" do
    delivery = webhook_deliveries(:completed_delivery)
    assert_not_includes WebhookDelivery.stale, delivery
  end

  # ============================================================================
  # DELIVERY ENQUEUE
  # ============================================================================

  test "enqueues delivery job after create" do
    assert_enqueued_with(job: Webhooks::DeliveryJob) do
      WebhookDelivery.create!(
        webhook: webhooks(:active_webhook),
        incident_event: incident_events(:inc1_created),
        event_type: IncidentEvent::INCIDENT_CREATED
      )
    end
  end
end
