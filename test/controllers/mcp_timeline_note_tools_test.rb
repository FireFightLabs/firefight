require "test_helper"

class McpTimelineNoteToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @note = @incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      metadata: {
        kind: "root_cause",
        statement: "Alice identified the migration lock as the root cause",
        message_id: "1.001"
      }
    )

    _, @personal_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
  end

  test "tools/list offers dismiss_timeline_note as a write tool" do
    tool = rpc("tools/list").dig("result", "tools").find { |entry| entry["name"] == Mcp::Tools::DISMISS_TIMELINE_NOTE }

    assert tool
    assert_not tool.dig("annotations", "readOnlyHint")
  end

  test "dismissing a note marks it and reports what was dismissed" do
    content, is_error = call_tool(Mcp::Tools::DISMISS_TIMELINE_NOTE, {
      incident: @incident.identifier, note_id: @note.id
    })

    assert_not is_error
    assert content["dismissed"]
    assert_equal "Alice identified the migration lock as the root cause", content["statement"]
    assert @note.reload.dismissed?
    assert_equal @membership.display_name, @note.metadata["dismissed_by_name"]
  end

  test "a dismissed note stops being returned by get_incident" do
    call_tool(Mcp::Tools::DISMISS_TIMELINE_NOTE, { incident: @incident.identifier, note_id: @note.id })

    content, = call_tool(Mcp::Tools::GET_INCIDENT, { incident: @incident.identifier })

    assert_not_includes content["timeline"].map { |entry| entry["event"] }, IncidentEvent::MILESTONE_NOTED
  end

  test "get_incident names the kind so an agent can ask for the root cause" do
    content, = call_tool(Mcp::Tools::GET_INCIDENT, { incident: @incident.identifier })
    entry = content["timeline"].find { |row| row["event"] == IncidentEvent::MILESTONE_NOTED }

    assert_equal "root_cause", entry["kind"]
    assert_equal "noted Alice identified the migration lock as the root cause", entry["description"]
  end

  test "an event that is not an AI note is refused with the reason" do
    pin = @incident.incident_events.create!(event_type: IncidentEvent::MESSAGE_PINNED, metadata: {})

    _, is_error, text = call_tool(Mcp::Tools::DISMISS_TIMELINE_NOTE, {
      incident: @incident.identifier, note_id: pin.id
    })

    assert is_error
    assert_equal "Only AI-noted milestones can be dismissed.", text
  end

  test "a note id from another incident is not found" do
    other = incidents(:resolved_minor_ws1)
    stray = other.incident_events.create!(event_type: IncidentEvent::MILESTONE_NOTED, metadata: { statement: "x" })

    _, is_error = call_tool(Mcp::Tools::DISMISS_TIMELINE_NOTE, {
      incident: @incident.identifier, note_id: stray.id
    })

    assert is_error
    assert_not stray.reload.dismissed?
  end

  private

  def rpc(method, params = {}, id: 1, token: @personal_token)
    post mcp_path,
         params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {}, token: @personal_token)
    result = rpc("tools/call", { name: name, arguments: arguments }, token: token).fetch("result")
    [ result["structuredContent"] || {}, result["isError"], result.dig("content", 0, "text") ]
  end
end
