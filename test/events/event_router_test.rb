require "test_helper"

class EventRouterTest < ActiveSupport::TestCase
  setup do
    @event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: "fake-id",
      user_id: "fake-user",
      data: { "severity" => "critical" },
      occurred_at: Time.current
    )
  end

  test "routes known event type without error" do
    assert_nothing_raised do
      EventRouter.route(@event)
    end
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

  test "subscribers arrays are empty in phase 1" do
    EventRouter::SUBSCRIBERS.each do |event_type, subscribers|
      assert_equal [], subscribers, "#{event_type} should have no subscribers in phase 1"
    end
  end
end
