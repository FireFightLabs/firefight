require "test_helper"

class EventRouterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: "fake-id",
      user_id: "fake-user",
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

  test "all event types are registered" do
    IncidentEvent::EVENT_TYPES.each do |event_type|
      assert EventRouter::SUBSCRIBERS.key?(event_type),
        "EventRouter should have subscribers entry for #{event_type}"
    end
  end

  test "subscribable events have webhook subscriber" do
    Webhook::SUBSCRIBABLE_EVENTS.each do |event_type|
      assert_includes EventRouter::SUBSCRIBERS[event_type], Webhooks::EventSubscriber,
        "#{event_type} should have Webhooks::EventSubscriber"
    end
  end

  test "non-subscribable events have no subscribers" do
    non_subscribable = IncidentEvent::EVENT_TYPES - Webhook::SUBSCRIBABLE_EVENTS
    non_subscribable.each do |event_type|
      assert_equal [], EventRouter::SUBSCRIBERS[event_type],
        "#{event_type} should have no subscribers"
    end
  end
end
