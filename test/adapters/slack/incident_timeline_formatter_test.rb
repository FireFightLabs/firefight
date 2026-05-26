require "test_helper"

class Slack::IncidentTimelineFormatterTest < ActiveSupport::TestCase
  fixtures :incident_events, :incidents, :incident_statuses, :incident_severities, :incident_lifecycle_stages, :workspace_memberships, :workspaces, :users

  test "renders archived flag for file shared events" do
    event = incident_events(:inc1_created)
    event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: {
        file_name: "runbook.png",
        mime_type: "image/png",
        user_id: "U123",
        blob_id: 10,
        permalink: "https://workspace.slack.com/archives/C123/p123"
      }
    )

    text = Slack::IncidentTimelineFormatter.to_text(event)

    assert_includes text, "File shared"
    assert_includes text, "Open in Slack"
  end

  test "renders action description when eventable has no message" do
    event = incident_events(:inc1_created)
    event.update!(event_type: IncidentEvent::ACTION_CREATED, metadata: {})
    event.stubs(:eventable).returns(Struct.new(:description).new("Rollback task created"))

    text = Slack::IncidentTimelineFormatter.to_text(event)

    assert_includes text, "Action created"
    assert_includes text, "Rollback task created"
  end
end
