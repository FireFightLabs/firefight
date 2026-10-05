require "test_helper"

class IncidentFileArchivalServiceTest < ActiveSupport::TestCase
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

  test "two events whose ids start with the same digits each keep their own file" do
    incident = incidents(:active_critical_ws1)
    first = file_event(incident, "572f0000-0000-4000-8000-000000000001", "first.txt")
    second = file_event(incident, "572a0000-0000-4000-8000-000000000002", "second.txt")
    Slack::Client.stubs(:download_file).returns({ body: "first bytes", content_type: "text/plain" })
      .then.returns({ body: "second bytes", content_type: "text/plain" })

    IncidentFileArchivalService.archive!(incident_event: first, slack_file: slack_file("first.txt"))
    IncidentFileArchivalService.archive!(incident_event: second, slack_file: slack_file("second.txt"))

    assert_equal "first bytes", IncidentEvent.find(first.id).archived_file.download
    assert_equal "second bytes", IncidentEvent.find(second.id).archived_file.download
  end

  private

  def file_event(incident, id, name)
    incident.incident_events.create!(id: id, event_type: IncidentEvent::MESSAGE_FILE_SHARED, metadata: { file_name: name })
  end

  def slack_file(name) = { "id" => "F-#{name}", "name" => name, "url_private_download" => "https://files.slack.com/files-pri/T1/#{name}" }
end
