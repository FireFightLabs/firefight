require "test_helper"

class Events::MessageHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )
  end

  test "creates file shared event when message includes files" do
    stub_get_permalink

    assert_difference "IncidentEvent.count", 1 do
      Events::MessageHandler.execute(Platforms::SLACK, file_message_payload)
    end

    assert_enqueued_jobs 1, only: ArchiveIncidentFileJob

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::MESSAGE_FILE_SHARED)
    assert_equal @member, event.user
    assert_equal "runbook.png", event.metadata["file_name"]
    assert_equal "image/png", event.metadata["mime_type"]
    assert_equal "1234567890.123456", event.metadata["message_ts"]
  end

  test "ignores unsupported message subtype" do
    assert_no_difference "IncidentEvent.count" do
      payload = file_message_payload
      payload["event"]["subtype"] = "message_changed"
      Events::MessageHandler.execute(Platforms::SLACK, payload)
    end
  end

  private

  def file_message_payload
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => "message",
        "channel" => @incident.channel_id,
        "user" => @member.platform_user_id,
        "ts" => "1234567890.123456",
        "thread_ts" => "1234567890.100000",
        "text" => "Sharing screenshot",
        "files" => [
          {
            "id" => "F123",
            "name" => "runbook.png",
            "mimetype" => "image/png",
            "size" => 12345
          }
        ]
      }
    }
  end
end
