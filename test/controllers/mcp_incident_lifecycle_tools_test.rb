require "test_helper"

# An agent running an incident the way a person does: open it, say what it
# finds, move it, close it. Everything here goes through the same forms and the
# same services the Slack modal and the dashboard use.
class McpIncidentLifecycleToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)

    _, @personal_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )

    stub_post_message
    stub_update_message
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_create_channel
    stub_invite_to_channel
  end

  test "every incident-write tool is offered as a write, not a read" do
    tools = rpc("tools/list").dig("result", "tools").index_by { |tool| tool["name"] }

    [ Mcp::Tools::DECLARE_INCIDENT, Mcp::Tools::POST_INCIDENT_UPDATE, Mcp::Tools::RESOLVE_INCIDENT,
      Mcp::Tools::CANCEL_INCIDENT, Mcp::Tools::REOPEN_INCIDENT ].each do |name|
      assert tools[name], "#{name} should be offered"
      assert_not tools[name].dig("annotations", "readOnlyHint"), "#{name} should not be read-only"
    end
  end

  # The scenario: something arrives, an agent decides it is an incident, opens
  # one, works it, and closes it.

  test "an agent declares an incident and is recorded as having declared it" do
    content, is_error = call_tool(Mcp::Tools::DECLARE_INCIDENT, {
      answers: { name: "Checkout failing for EU", severity: severity_slug }
    })

    assert_not is_error, content.inspect
    incident = @workspace.incidents.find_by!(name: "Checkout failing for EU")
    assert_equal Incident::SOURCE_MCP, incident.source
    assert_equal @membership, incident.declared_by
    assert content["declared"]
    assert_equal incident.identifier, content["identifier"]
  end

  # declared_by is polymorphic now, so a service key can be recorded as the
  # declarer too. Before, only a person could, and a key had to borrow one.
  test "a service key is recorded as declaring, not a person it borrowed" do
    key, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Triage bot",
      permissions: { "incidents" => %w[read create update] }
    )

    call_tool(Mcp::Tools::DECLARE_INCIDENT, {
      answers: { name: "Raised by a machine", severity: severity_slug }
    }, token: token)

    incident = @workspace.incidents.find_by!(name: "Raised by a machine")
    assert_equal key, incident.declared_by
    assert_equal "api_key", incident.declared_by.actor_kind
  end

  # The point of agents: one takes part under its own name, with only the
  # abilities it was granted, and the record says the agent did it.
  test "an agent declares under its own name, not a person's" do
    agent, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Support agent", slug: "support_agent",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create] }
    )

    _, is_error = call_tool(Mcp::Tools::DECLARE_INCIDENT, {
      answers: { name: "Raised from a support ticket", severity: severity_slug }
    }, token: token)

    assert_not is_error
    incident = @workspace.incidents.find_by!(name: "Raised from a support ticket")
    assert_equal agent, incident.declared_by
    assert_equal "agent", incident.declared_by.actor_kind
    assert_equal "Support agent", incident.declared_by.actor_display_name
  end

  test "an agent granted only reads cannot move an incident" do
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Watcher", slug: "watcher",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    )

    _, is_error = call_tool(
      Mcp::Tools::CANCEL_INCIDENT, { incident: @incident.identifier, answers: {} }, token: token
    )

    assert is_error
    assert_not @incident.reload.canceled?
  end

  test "an agent with no grants can authenticate and do nothing" do
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Ungranted", slug: "ungranted"
    )

    _, is_error = call_tool(Mcp::Tools::DECLARE_INCIDENT, {
      answers: { name: "Should never exist", severity: severity_slug }
    }, token: token)

    assert is_error
    assert_nil @workspace.incidents.find_by(name: "Should never exist")
  end

  # Rotation moves the credential, never the identity: the same agent keeps
  # its grants and stays the actor on everything it does next.
  test "an agent keeps its identity across a token rotation" do
    agent, = create_agent(
      workspace: @workspace, created_by: @membership, name: "Rotator", slug: "rotator",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create] }
    )
    _, rotated = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, agent: agent, name: "Rotator token 2"
    )

    _, is_error = call_tool(Mcp::Tools::DECLARE_INCIDENT, {
      answers: { name: "After the rotation", severity: severity_slug }
    }, token: rotated)

    assert_not is_error
    assert_equal agent, @workspace.incidents.find_by!(name: "After the rotation").declared_by
  end

  test "declaring says what the workspace asks for rather than failing silently" do
    _, is_error, text = call_tool(Mcp::Tools::DECLARE_INCIDENT, { answers: { name: "No severity" } })

    assert is_error
    assert_match(/required/i, text)
    assert_match(/get_form/, text)
    assert_nil @workspace.incidents.find_by(name: "No severity")
  end

  test "an agent posts an update and the channel gets the message" do
    _, is_error = call_tool(Mcp::Tools::POST_INCIDENT_UPDATE, {
      incident: @incident.identifier,
      answers: {
        message: "Connection pool exhausted on replica 2, draining now",
        status: @incident.incident_status.slug,
        severity: @incident.incident_severity.slug
      }
    })

    assert_not is_error
    update = @incident.incident_updates.find_by!(message: "Connection pool exhausted on replica 2, draining now")
    assert_equal IncidentUpdate::UPDATED, update.update_type
  end

  test "an agent resolves an incident and the timeline names the agent" do
    _, is_error = call_tool(Mcp::Tools::RESOLVE_INCIDENT, {
      incident: @incident.identifier,
      answers: { severity: @incident.incident_severity.slug, summary: "Pool limit raised" }
    })

    assert_not is_error
    assert @incident.reload.closed?
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_RESOLVED)
    assert_equal @membership, event.actor
  end

  test "an agent cancels an incident that was not one" do
    _, is_error = call_tool(Mcp::Tools::CANCEL_INCIDENT, { incident: @incident.identifier, answers: {} })

    assert_not is_error
    assert @incident.reload.canceled?
  end

  test "an agent reopens something that came back" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @membership
    )

    _, is_error = call_tool(Mcp::Tools::REOPEN_INCIDENT, {
      incident: @incident.identifier, reason: "Error rate climbing again"
    })

    assert_not is_error
    assert_equal @workspace.default_live_status, @incident.reload.incident_status
  end

  test "reopening something already active says so rather than doing nothing" do
    _, is_error, text = call_tool(Mcp::Tools::REOPEN_INCIDENT, { incident: @incident.identifier })

    assert is_error
    assert_match(/already active/, text)
  end

  # The resolver is the same one Slack and the dashboard read, so an agent
  # cannot write a field this workspace never asked for.

  test "an answer the form never asked for is refused" do
    _, is_error, text = call_tool(Mcp::Tools::POST_INCIDENT_UPDATE, {
      incident: @incident.identifier,
      answers: {
        message: "Fine", status: @incident.incident_status.slug,
        severity: @incident.incident_severity.slug, invented_field: "nope"
      }
    })

    assert is_error
    assert_match(/Unknown fields/, text)
  end

  test "a read-only token cannot move an incident" do
    _, is_error = call_tool(
      Mcp::Tools::CANCEL_INCIDENT, { incident: @incident.identifier, answers: {} },
      token: "ff_test_read_only_token_12345678"
    )

    assert is_error
    assert_not @incident.reload.canceled?
  end

  test "another workspace's incident is not reachable" do
    _, is_error = call_tool(Mcp::Tools::RESOLVE_INCIDENT, { incident: incidents(:active_p0_ws2).identifier })

    assert is_error
  end

  private

  def severity_slug
    @workspace.incident_severities.active.first.slug
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
end
