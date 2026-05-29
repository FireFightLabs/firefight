require "test_helper"

class Webhooks::DispatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_events,
           :webhooks, :webhook_delinquency_trackers

  setup do
    @event = incident_events(:inc1_created)
    @event_hash = {
      "event_id" => @event.id,
      "event_type" => @event.event_type,
      "incident_id" => @event.incident_id,
      "actor_type" => @event.actor_id ? "WorkspaceMembership" : nil, "actor_id" => @event.actor_id,
      "data" => @event.metadata,
      "occurred_at" => @event.created_at.iso8601(6)
    }
  end

  test "creates webhook deliveries for matching webhooks" do
    assert_difference -> { WebhookDelivery.count }, 1 do
      Webhooks::DispatchJob.perform_now(@event_hash)
    end

    delivery = WebhookDelivery.find_by!(webhook: webhooks(:active_webhook), incident_event: @event)
    assert_equal "incident.created", delivery.event_type
  end

  test "skips inactive webhooks" do
    inactive = webhooks(:inactive_webhook)
    assert_not inactive.active?

    Webhooks::DispatchJob.perform_now(@event_hash)

    assert_not WebhookDelivery.exists?(webhook: inactive, incident_event: @event)
  end

  test "skips webhooks not subscribed to event type" do
    event = incident_events(:inc1_updated)
    event_hash = {
      "event_id" => event.id,
      "event_type" => IncidentEvent::LEAD_ASSIGNED,
      "incident_id" => event.incident_id,
      "actor_type" => event.actor_id ? "WorkspaceMembership" : nil, "actor_id" => event.actor_id,
      "data" => event.metadata,
      "occurred_at" => event.created_at.iso8601(6)
    }

    # active_webhook subscribes to incident.created, incident.resolved, incident.updated
    # lead.assigned is not in its subscribed_events, so no new deliveries should be created
    assert_no_difference -> { WebhookDelivery.count } do
      Webhooks::DispatchJob.perform_now(event_hash)
    end
  end

  test "does not create deliveries for other workspace webhooks" do
    Webhooks::DispatchJob.perform_now(@event_hash)

    # workspace_two_webhook should not get a delivery for ws1 incident
    assert_not WebhookDelivery.exists?(webhook: webhooks(:workspace_two_webhook), incident_event: @event)
  end
end
