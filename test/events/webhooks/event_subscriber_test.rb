require "test_helper"

class Webhooks::EventSubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  test "enqueues dispatch job with event hash" do
    event = DomainEvent.new(
      event_id: incident_events(:inc1_created).id,
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: incidents(:active_critical_ws1).id,
      occurred_at: Time.current
    )

    assert_enqueued_with(job: Webhooks::DispatchJob) do
      Webhooks::EventSubscriber.handle(event)
    end
  end
end
