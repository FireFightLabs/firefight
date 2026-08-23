require "test_helper"

class Events::MessageHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


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

  test "new message creates a transcript row with resolved fields" do
    Events::MessageHandler.execute(@workspace, text_message_payload)

    message = @incident.incident_transcript_messages.find_by!(slack_ts: "1234567890.000100")
    assert_equal @workspace, message.workspace
    assert_equal @member, message.workspace_membership
    assert_equal @member.platform_user_id, message.slack_user_id
    assert_equal "investigating db replica lag", message.content
    assert_nil message.slack_thread_ts
    assert_in_delta Time.at(1234567890.000100), message.posted_at, 0.001
  end

  test "threaded reply preserves parent ts" do
    payload = text_message_payload
    payload["event"]["thread_ts"] = "1234567890.000000"
    Events::MessageHandler.execute(@workspace, payload)

    message = @incident.incident_transcript_messages.find_by!(slack_ts: "1234567890.000100")
    assert_equal "1234567890.000000", message.slack_thread_ts
  end

  test "duplicate delivery does not raise and does not dup" do
    Events::MessageHandler.execute(@workspace, text_message_payload)
    Events::MessageHandler.execute(@workspace, text_message_payload)

    assert_equal 1, @incident.incident_transcript_messages.where(slack_ts: "1234567890.000100").count
  end

  test "edit updates content on existing row" do
    Events::MessageHandler.execute(@workspace, text_message_payload)
    Events::MessageHandler.execute(@workspace, edit_payload(ts: "1234567890.000100", text: "new context"))

    message = @incident.incident_transcript_messages.find_by!(slack_ts: "1234567890.000100")
    assert_equal "new context", message.content
  end

  test "edit on unknown ts is a no-op" do
    assert_no_difference "IncidentTranscriptMessage.count" do
      Events::MessageHandler.execute(@workspace, edit_payload(ts: "9999.999", text: "ghost"))
    end
  end

  test "delete soft-deletes the existing row" do
    Events::MessageHandler.execute(@workspace, text_message_payload)
    Events::MessageHandler.execute(@workspace, delete_payload(ts: "1234567890.000100"))

    message = @incident.incident_transcript_messages.find_by!(slack_ts: "1234567890.000100")
    assert_not_nil message.deleted_at
    assert_not_includes IncidentTranscriptMessage.kept, message
  end

  test "delete on unknown ts is a no-op" do
    assert_nothing_raised do
      Events::MessageHandler.execute(@workspace, delete_payload(ts: "9999.999"))
    end
  end

  test "file_share still creates IncidentEvent and enqueues archival job" do
    stub_get_permalink

    assert_difference "IncidentEvent.count", 1 do
      Events::MessageHandler.execute(@workspace, file_message_payload)
    end

    assert_enqueued_jobs 1, only: ArchiveIncidentFileJob
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::MESSAGE_FILE_SHARED)
    assert_equal @member, event.actor
    assert_equal "runbook.png", event.metadata["file_name"]
  end

  test "a redelivered file_share does not create a second event or archival job" do
    stub_get_permalink

    assert_difference "IncidentEvent.count", 1 do
      Events::MessageHandler.execute(@workspace, file_message_payload)
      Events::MessageHandler.execute(@workspace, file_message_payload)
    end

    assert_enqueued_jobs 1, only: ArchiveIncidentFileJob
  end

  test "file_share also creates a transcript row" do
    stub_get_permalink

    Events::MessageHandler.execute(@workspace, file_message_payload)

    assert @incident.incident_transcript_messages.exists?(slack_ts: "1234567890.123456")
  end

  test "bot messages skip transcript ingest" do
    payload = text_message_payload
    payload["event"]["bot_id"] = "B_RUNAWAY_BOT"

    assert_no_difference "IncidentTranscriptMessage.count" do
      Events::MessageHandler.execute(@workspace, payload)
    end
  end

  test "bot file uploads still create the file event and archival job" do
    stub_get_permalink
    payload = file_message_payload
    payload["event"]["bot_id"] = "B_INTEGRATION"

    assert_no_difference "IncidentTranscriptMessage.count" do
      assert_difference "IncidentEvent.count", 1 do
        Events::MessageHandler.execute(@workspace, payload)
      end
    end

    assert_enqueued_jobs 1, only: ArchiveIncidentFileJob
  end

  test "ignores truly unsupported subtype" do
    payload = text_message_payload
    payload["event"]["subtype"] = "channel_topic"

    assert_no_difference "IncidentTranscriptMessage.count" do
      Events::MessageHandler.execute(@workspace, payload)
    end
  end

  private

  def text_message_payload
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => "message",
        "channel" => @incident.channel_id,
        "user" => @member.platform_user_id,
        "ts" => "1234567890.000100",
        "text" => "investigating db replica lag"
      }
    }
  end

  def edit_payload(ts:, text:)
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => "message",
        "subtype" => Identifiers::MESSAGE_SUBTYPE_MESSAGE_CHANGED,
        "channel" => @incident.channel_id,
        "ts" => "9999999999.000000",
        "message" => {
          "ts" => ts,
          "user" => @member.platform_user_id,
          "text" => text
        }
      }
    }
  end

  def delete_payload(ts:)
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => "message",
        "subtype" => Identifiers::MESSAGE_SUBTYPE_MESSAGE_DELETED,
        "channel" => @incident.channel_id,
        "ts" => "9999999999.000000",
        "deleted_ts" => ts
      }
    }
  end

  def file_message_payload
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => "message",
        "subtype" => Identifiers::MESSAGE_SUBTYPE_FILE_SHARE,
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
