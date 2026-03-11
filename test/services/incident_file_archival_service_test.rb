require "test_helper"

class IncidentFileArchivalServiceTest < ActiveSupport::TestCase
  fixtures :incident_events, :incidents, :workspaces, :incident_statuses, :incident_severities, :incident_lifecycle_stages, :workspace_memberships, :users

  test "backfills blob metadata after successful archive" do
    incident_event = incident_events(:inc1_created)
    incident_event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: {
        details: {
          file_name: "runbook.png",
          mime_type: "image/png"
        }
      }
    )

    adapter = mock("workspace_adapter")
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:archive_slack_file).returns({
      archived: true,
      object_key: "artifacts/abc",
      blob_id: 123,
      byte_size: 456,
      checksum: "xyz"
    })

    IncidentFileArchivalService.archive!(incident_event: incident_event, slack_file: { "id" => "F123" })

    details = incident_event.reload.details
    assert_equal "artifacts/abc", details["object_key"]
    assert_equal 123, details["blob_id"]
    assert_equal 456, details["byte_size"]
    assert_equal "xyz", details["checksum"]
  end
end
