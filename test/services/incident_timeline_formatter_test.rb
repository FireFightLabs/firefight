require "test_helper"

class IncidentTimelineFormatterTest < ActiveSupport::TestCase
  fixtures :incident_events, :incidents, :incident_statuses, :incident_severities, :incident_lifecycle_stages, :workspace_memberships, :workspaces, :users

  test "renders archived flag for file shared events" do
    event = incident_events(:inc1_created)
    event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: {
        details: {
          file_name: "runbook.png",
          mime_type: "image/png",
          user_id: "U123",
          blob_id: 10
        }
      }
    )

    text = IncidentTimelineFormatter.to_text(event)

    assert_includes text, "File shared"
    assert_includes text, "archived"
  end
end
