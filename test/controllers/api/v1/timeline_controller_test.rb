require "test_helper"

class Api::V1::TimelineControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @note = @incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      created_at: 2.hours.ago,
      metadata: {
        kind: "root_cause",
        statement: "Alice identified the migration lock as the root cause",
        member_name: @member.display_name,
        message_id: "1.001",
        message_text: "it's the migration lock",
        permalink: "https://slack.test/p1",
        said_at: 2.hours.ago.utc.iso8601
      }
    )
  end

  test "the timeline returns notes with their kind, quote and link" do
    get api_v1_incident_timeline_index_url(@incident), headers: api_headers, as: :json

    assert_response :success
    note = json_response["events"].find { |event| event["event_type"] == IncidentEvent::MILESTONE_NOTED }
    assert_equal "root_cause", note.dig("milestone", "kind")
    assert_equal "Alice identified the migration lock as the root cause", note.dig("milestone", "statement")
    assert_equal @member.display_name, note.dig("milestone", "said_by")
    assert_equal "it's the migration lock", note.dig("milestone", "message_text")
    assert_equal "https://slack.test/p1", note.dig("milestone", "permalink")
    assert note["automated"]
    assert_nil note["actor"]
  end

  test "events that are not notes carry a null milestone" do
    get api_v1_incident_timeline_index_url(@incident), headers: api_headers, as: :json

    other = json_response["events"].find { |event| event["event_type"] != IncidentEvent::MILESTONE_NOTED }
    assert_nil other["milestone"]
  end

  test "a read-only key cannot dismiss a note" do
    patch dismiss_api_v1_incident_timeline_url(@incident, @note),
          headers: api_headers(token: "ff_test_read_only_token_12345678"), as: :json

    assert_response :forbidden
    assert_not @note.reload.dismissed?
  end

  test "dismissing a note through the API removes it from the timeline" do
    patch dismiss_api_v1_incident_timeline_url(@incident, @note), headers: api_headers, as: :json

    assert_response :success
    assert_not_nil json_response.dig("event", "milestone", "dismissed_at")

    get api_v1_incident_timeline_index_url(@incident), headers: api_headers, as: :json
    assert_empty json_response["events"].select { |event| event["event_type"] == IncidentEvent::MILESTONE_NOTED }
  end

  test "dismissing something that is not a note is refused with the reason" do
    pin = @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, metadata: {})

    patch dismiss_api_v1_incident_timeline_url(@incident, pin), headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "Only AI-noted milestones can be dismissed.", json_response["error"]
  end

  test "another workspace's incident is not reachable" do
    other = incidents(:active_p0_ws2)

    get api_v1_incident_timeline_index_url(other), headers: api_headers, as: :json

    assert_response :not_found
  end
end
