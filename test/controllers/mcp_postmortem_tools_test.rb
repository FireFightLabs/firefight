require "test_helper"

# Writing up an incident from the same connection that worked it. An agent
# could declare, run and close one and then not write it up, which left the
# loop open.
class McpPostmortemToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)

    _, @personal_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
    @agent, @agent_token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Scribe", slug: "scribe",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read update] }
    )

    stub_post_message
    stub_update_message
    stub_set_channel_topic
  end

  test "an incident still open has nothing to write up" do
    _, is_error, text = call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier })

    assert is_error
    assert_match(/still open/, text)
    assert_nil @incident.reload.postmortem
  end

  test "a canceled incident has nothing to write up either" do
    IncidentLifecycleService.new(@workspace).cancel_with_default_status(@incident, changed_by: @membership)

    _, is_error, text = call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier })

    assert is_error
    assert_match(/canceled/, text)
  end

  # The whole point: the agent that worked it writes it up, under its own name.
  test "an agent starts a blank postmortem and is recorded as its author" do
    resolve!

    content, is_error = call_tool(Mcp::Tools::START_POSTMORTEM, {
      incident: @incident.identifier
    }, token: @agent_token)

    assert_not is_error, content.inspect
    postmortem = @incident.reload.postmortem
    assert_equal @agent, postmortem.generated_by
    assert_equal Postmortem::STATUS_DRAFT, postmortem.status
    assert_equal @agent.name, content["written_by"]
  end

  test "starting one twice says it already has one" do
    resolve!
    call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier })

    _, is_error, text = call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier })

    assert is_error
    assert_match(/already has a postmortem/, text)
  end

  test "an agent writes the body and the timeline records the edit" do
    resolve!
    call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier }, token: @agent_token)

    content, is_error = call_tool(Mcp::Tools::UPDATE_POSTMORTEM, {
      incident: @incident.identifier,
      html: "<h2>What happened</h2><p>The connection pool was exhausted.</p>"
    }, token: @agent_token)

    assert_not is_error, content.inspect
    assert_includes @incident.reload.postmortem.html_content, "connection pool was exhausted"
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::POSTMORTEM_EDITED)
    assert_equal @agent, event.actor
  end

  test "the markup is sanitised down to what the editor allows" do
    resolve!
    call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier })

    call_tool(Mcp::Tools::UPDATE_POSTMORTEM, {
      incident: @incident.identifier,
      html: "<p>Fine</p><script>alert('no')</script>"
    })

    html = @incident.reload.postmortem.html_content
    assert_includes html, "Fine"
    assert_not_includes html, "<script>"
  end

  test "reading one back returns the body and who wrote it" do
    resolve!
    call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier }, token: @agent_token)
    call_tool(Mcp::Tools::UPDATE_POSTMORTEM, {
      incident: @incident.identifier, html: "<p>Root cause was the pooler.</p>"
    }, token: @agent_token)

    content, is_error = call_tool(Mcp::Tools::GET_POSTMORTEM, { incident: @incident.identifier })

    assert_not is_error, content.inspect
    assert_includes content["html"], "Root cause was the pooler"
    assert_equal @agent.name, content["written_by"]
  end

  test "an incident with no postmortem says so rather than returning an empty one" do
    resolve!

    _, is_error, text = call_tool(Mcp::Tools::GET_POSTMORTEM, { incident: @incident.identifier })

    assert is_error
    assert_match(/no postmortem yet/, text)
  end

  test "moving it to review records where it now sits" do
    resolve!
    call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier })

    content, is_error = call_tool(Mcp::Tools::SET_POSTMORTEM_STATUS, {
      incident: @incident.identifier, status: Postmortem::STATUS_IN_REVIEW
    })

    assert_not is_error, content.inspect
    assert_equal Postmortem::STATUS_IN_REVIEW, @incident.reload.postmortem.status
  end

  test "an agent granted only reads cannot write one up" do
    resolve!
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Watcher", slug: "watcher",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    )

    _, is_error = call_tool(Mcp::Tools::START_POSTMORTEM, { incident: @incident.identifier }, token: token)

    assert is_error
    assert_nil @incident.reload.postmortem
  end

  private

  def resolve!
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @membership
    )
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
