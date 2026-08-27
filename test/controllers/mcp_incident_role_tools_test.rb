require "test_helper"

class McpIncidentRoleToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @lead_role = incident_roles(:incident_lead_ws1)
    @comms_role = incident_roles(:communications_lead_ws1)

    _, @personal_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )

    stub_post_message
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_update_message
    stub_post_ephemeral
  end

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

  test "tools/list includes assign_incident_role as a write tool" do
    tool = rpc("tools/list").dig("result", "tools").find { |t| t["name"] == Mcp::Tools::ASSIGN_INCIDENT_ROLE }

    assert tool
    assert_not tool.dig("annotations", "readOnlyHint")
  end

  test "assigns a custom role by email" do
    content, is_error = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @comms_role.slug, member: @membership.email
    })

    assert_not is_error
    assert content["assigned"]
    assert_equal @comms_role.slug, content["role"]
    assert_equal @membership, @incident.reload.role_holder(@comms_role)
  end

  test "assigns a custom role by platform user id" do
    _, is_error = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @comms_role.slug, member: @membership.platform_user_id
    })

    assert_not is_error
    assert_equal @membership, @incident.reload.role_holder(@comms_role)
  end

  test "assigning replaces the current holder" do
    assert_equal @bob, @incident.role_holder(@comms_role)

    call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @comms_role.slug, member: @membership.email
    })

    assert_equal 1, @incident.reload.incident_role_assignments.where(incident_role: @comms_role).count
    assert_equal @membership, @incident.role_holder(@comms_role)
  end

  test "omitting member clears a custom role" do
    content, is_error = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @comms_role.slug
    })

    assert_not is_error
    assert_not content["assigned"]
    assert_nil @incident.reload.role_holder(@comms_role)
  end

  test "assigning the lead routes through the lead path" do
    _, is_error = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @lead_role.slug, member: @bob.email
    })

    assert_not is_error
    assert_equal @bob, @incident.reload.lead
    assert @incident.incident_events.exists?(event_type: IncidentEvent::LEAD_ASSIGNED)
  end

  test "refuses to assign the lead once the incident is over" do
    @incident.update!(incident_status: incident_statuses(:resolved_ws1))

    _, is_error, text = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @lead_role.slug, member: @bob.email
    })

    assert is_error
    assert_equal "#{@incident.identifier} is closed, so it can no longer be assigned a lead.", text
    assert_nil @incident.reload.lead
  end

  test "refuses any role once the incident is over" do
    @incident.update!(incident_status: incident_statuses(:resolved_ws1))

    _, is_error, text = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @comms_role.slug, member: @membership.email
    })

    assert is_error
    assert_equal "#{@incident.identifier} is closed, so its Communications Lead can no longer be changed.", text
  end

  test "refuses to clear the lead" do
    @incident.assign_role!(@lead_role, @bob)

    _, is_error, text = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @lead_role.slug
    })

    assert is_error
    assert_equal @lead_role.unassign_blocked_reason, text
    assert_equal @bob, @incident.reload.lead
  end

  test "an unknown role lists the ones that exist" do
    _, is_error, text = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: "not_a_role", member: @membership.email
    })

    assert is_error
    assert_includes text, @comms_role.slug
  end

  test "an unknown member is named in the error" do
    _, is_error, text = call_tool(Mcp::Tools::ASSIGN_INCIDENT_ROLE, {
      incident: @incident.identifier, role: @comms_role.slug, member: "nobody@example.com"
    })

    assert is_error
    assert_includes text, "nobody@example.com"
    assert_equal @bob, @incident.reload.role_holder(@comms_role)
  end

  test "get_incident reports every role and who holds it" do
    content, is_error = call_tool(Mcp::Tools::GET_INCIDENT, { incident: @incident.identifier })

    assert_not is_error
    comms = content["roles"].find { |role| role["slug"] == @comms_role.slug }
    assert_equal @bob.display_name, comms["held_by"]
    lead = content["roles"].find { |role| role["slug"] == @lead_role.slug }
    assert_nil lead["held_by"]
  end
end
