require "test_helper"

class Investigation::TimelineTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @investigation = @incident.workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "Checkout returns 500" }
    )
  end

  test "a run's start is on its incident's timeline once, with what it was asked, and says nothing to webhooks" do
    Webhooks::EventSubscriber.expects(:handle).never

    2.times { @investigation.note_started! }

    started = @incident.incident_events.where(event_type: IncidentEvent::INVESTIGATION_STARTED).sole
    assert_equal SystemAgent.investigator, started.actor
    assert_equal "Checkout returns 500", started.metadata["message"]
    assert_equal "started an investigation", started.description
  end

  test "the answer is on the timeline, and a stop says why" do
    @investigation.note_answered!(Investigation::Finding.new(summary: "The 14:02 deploy halved the pool"))
    @investigation.note_stopped!(Investigation::BUDGET_SPENT)

    assert_equal "The 14:02 deploy halved the pool",
                 @incident.incident_events.find_by!(event_type: IncidentEvent::INVESTIGATION_ANSWERED).metadata["message"]
    assert_equal Investigation::BUDGET_SPENT,
                 @incident.incident_events.find_by!(event_type: IncidentEvent::INVESTIGATION_STOPPED).metadata["reason"]
  end
end
