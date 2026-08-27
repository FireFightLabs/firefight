require "test_helper"

class EventRouterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: "fake-id",
      actor_id: "fake-user",
      data: { "severity" => "critical" },
      occurred_at: Time.current
    )
  end

  test "routes known event type to subscribers" do
    Webhooks::EventSubscriber.expects(:handle).with(@event)
    EventRouter.route(@event)
  end

  test "logs warning for unknown event type" do
    event = DomainEvent.new(
      event_type: "unknown.event",
      incident_id: "fake-id",
      data: {},
      occurred_at: Time.current
    )

    Rails.logger.expects(:warn).with(has_entries(
      event: "event_router.unknown_event_type",
      event_type: "unknown.event"
    ))

    EventRouter.route(event)
  end

  test "every event type is either subscribable or named internal, exactly" do
    covered = Webhook::SUBSCRIBABLE_EVENTS + EventRouter::INTERNAL_ONLY

    assert_equal IncidentEvent::EVENT_TYPES.sort, covered.sort,
      "a new event type has to be a deliberate decision: subscribable or internal"
    assert_empty Webhook::SUBSCRIBABLE_EVENTS & EventRouter::INTERNAL_ONLY
  end

  test "an internal event routes nowhere and a subscribable one reaches the webhook subscriber" do
    Webhooks::EventSubscriber.expects(:handle).never
    EventRouter.route(DomainEvent.new(event_type: IncidentEvent::MESSAGE_PINNED, incident_id: "fake-id", actor_id: nil, data: {}, occurred_at: Time.current))

    Webhooks::EventSubscriber.expects(:handle).once
    EventRouter.route(@event)
  end
end
