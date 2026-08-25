require "test_helper"

class Events::PinHandlersTest < ActiveSupport::TestCase
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

  test "creates message pinned event with the message text" do
    stub_get_permalink
    stub_get_message(text: "Rolled back the deploy, error rate dropping")

    assert_difference "IncidentEvent.count", 1 do
      Events::PinAddedHandler.execute(@workspace, pin_payload("pin_added"))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::MESSAGE_PINNED)
    assert_equal @member, event.actor
    assert_equal "1234567890.111111", event.metadata["message_ts"]
    assert_equal "Rolled back the deploy, error rate dropping", event.metadata["message_text"]
  end

  test "records the pin even when the message text cannot be fetched" do
    stub_get_permalink
    Slack::Client.stubs(:get_message).raises(AdapterError::NotFound, "message_not_found")

    assert_difference "IncidentEvent.count", 1 do
      Events::PinAddedHandler.execute(@workspace, pin_payload("pin_added"))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::MESSAGE_PINNED)
    assert_nil event.metadata["message_text"]
  end

  test "creates message unpinned event" do
    stub_get_permalink
    stub_get_message

    assert_difference "IncidentEvent.count", 1 do
      Events::PinRemovedHandler.execute(@workspace, pin_payload("pin_removed"))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::MESSAGE_UNPINNED)
    assert_equal @member, event.actor
  end

  private

  def pin_payload(type)
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => type,
        "user" => @member.platform_user_id,
        "item" => {
          "type" => "message",
          "channel" => @incident.channel_id,
          "ts" => "1234567890.111111"
        }
      }
    }
  end
end
