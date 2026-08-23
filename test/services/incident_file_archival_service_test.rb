require "test_helper"

class IncidentFileArchivalServiceTest < ActiveSupport::TestCase
  fixtures :incident_events, :incidents, :workspaces, :incident_statuses, :incident_severities, :incident_lifecycle_stages, :workspace_memberships, :users

  test "backfills blob metadata after successful archive" do
    incident_event = incident_events(:inc1_created)
    incident_event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: {
        file_name: "runbook.png",
        mime_type: "image/png"
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

    metadata = incident_event.reload.metadata
    assert_equal "artifacts/abc", metadata["object_key"]
    assert_equal 123, metadata["blob_id"]
    assert_equal 456, metadata["byte_size"]
    assert_equal "xyz", metadata["checksum"]
  end

  test "an event whose artifact is already attached is not archived again" do
    incident_event = incident_events(:inc1_created)
    incident_event.update!(event_type: IncidentEvent::MESSAGE_FILE_SHARED, metadata: { file_name: "runbook.png" })
    incident_event.artifact.attach(io: StringIO.new("png"), filename: "runbook.png", content_type: "image/png")
    WorkspaceAdapter.expects(:for).never

    IncidentFileArchivalService.archive!(incident_event: incident_event, slack_file: { "id" => "F1" })
  end
end
