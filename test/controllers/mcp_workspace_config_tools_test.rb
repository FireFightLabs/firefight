require "test_helper"

# Configuring a workspace the way a person does on the settings screens, but
# from Claude Code. Every tool goes through the same model operations the
# screen calls, so a list changed here behaves as if it had been dragged.
class McpWorkspaceConfigToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)

    _, @admin_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Admin"
    )
  end

  test "the config tools are offered, and only the deletes are destructive" do
    tools = rpc("tools/list").dig("result", "tools").index_by { |tool| tool["name"] }

    [ Mcp::Tools::UPSERT_SEVERITY, Mcp::Tools::UPSERT_STATUS,
      Mcp::Tools::UPSERT_INCIDENT_TYPE, Mcp::Tools::UPSERT_INCIDENT_ROLE ].each do |name|
      assert tools[name], "#{name} should be offered"
      assert_not tools[name].dig("annotations", "destructiveHint"), "#{name} is not destructive"
    end

    [ Mcp::Tools::DELETE_SEVERITY, Mcp::Tools::DELETE_STATUS,
      Mcp::Tools::DELETE_INCIDENT_TYPE, Mcp::Tools::DELETE_INCIDENT_ROLE ].each do |name|
      assert tools[name].dig("annotations", "destructiveHint"), "#{name} is destructive"
    end
  end

  # The whole reason these are separate tools rather than one with a kind
  # argument: their payloads are not the same, and the schema has to say so.
  test "each list asks for its own fields and nothing it has no use for" do
    tools = rpc("tools/list").dig("result", "tools").index_by { |tool| tool["name"] }
    properties = ->(name) { tools[name].dig("inputSchema", "properties").keys }

    assert_includes properties.call(Mcp::Tools::UPSERT_SEVERITY), "rank"
    assert_not_includes properties.call(Mcp::Tools::UPSERT_SEVERITY), "lifecycle_stage"

    assert_includes properties.call(Mcp::Tools::UPSERT_STATUS), "lifecycle_stage"
    assert_not_includes properties.call(Mcp::Tools::UPSERT_STATUS), "rank"

    assert_not_includes properties.call(Mcp::Tools::UPSERT_INCIDENT_ROLE), "color"
    assert_not_includes properties.call(Mcp::Tools::UPSERT_INCIDENT_ROLE), "default"
  end

  test "one call names everything the workspace is configured with" do
    content, is_error = call_tool(Mcp::Tools::GET_WORKSPACE_CONFIG)

    assert_not is_error, content.inspect
    assert_equal @workspace.incident_severities.count, content["severities"].size
    assert content["statuses"].all? { |status| status["lifecycle_stage"].present? }
    assert content.key?("incident_roles")
    assert content.key?("webhooks")
  end

  test "creating a severity puts it at the end of the list" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_SEVERITY, {
      name: "SEV0", description: "Everything is on fire", rank: 1, color: "#e5484d"
    }, token: @admin_token)

    assert_not is_error, content.inspect
    severity = @workspace.incident_severities.find_by!(slug: "sev0")
    assert_equal 1, severity.rank
    assert_equal @workspace.incident_severities.maximum(:position), severity.position
    assert_equal "sev0", content["slug"]
  end

  test "creating without a name says so rather than failing at the database" do
    _, is_error, text = call_tool(Mcp::Tools::UPSERT_SEVERITY, { rank: 1 }, token: @admin_token)

    assert is_error
    assert_match(/name is required/, text)
  end

  # Renaming leaves the slug alone, because stored records point at it.
  test "renaming keeps the slug" do
    severity = @workspace.incident_severities.active.first

    content, is_error = call_tool(Mcp::Tools::UPSERT_SEVERITY, {
      slug: severity.slug, name: "Renamed"
    }, token: @admin_token)

    assert_not is_error, content.inspect
    assert_equal "Renamed", severity.reload.name
    assert_equal severity.slug, content["slug"]
  end

  test "a slug that resolves to nothing is an error, not a second one under a fresh slug" do
    assert_no_difference -> { @workspace.incident_severities.count } do
      _, is_error, text = call_tool(Mcp::Tools::UPSERT_SEVERITY, {
        slug: "not_a_severity", name: "Ghost"
      }, token: @admin_token)

      assert is_error
      assert_match(/Not found in this workspace/, text)
    end
  end

  test "a status is created into the lifecycle stage it names" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_STATUS, {
      name: "Mitigating", lifecycle_stage: IncidentLifecycleStage::ACTIVE
    }, token: @admin_token)

    assert_not is_error, content.inspect
    status = @workspace.incident_statuses.find_by!(slug: "mitigating")
    assert_equal IncidentLifecycleStage::ACTIVE, status.incident_lifecycle_stage.key
    assert_equal IncidentLifecycleStage::ACTIVE, content["lifecycle_stage"]
  end

  test "disabling retires an option without deleting it" do
    type = @workspace.incident_types.active.first

    _, is_error = call_tool(Mcp::Tools::UPSERT_INCIDENT_TYPE, {
      slug: type.slug, enabled: false
    }, token: @admin_token)

    assert_not is_error
    assert_not_nil type.reload.deleted_at
    assert @workspace.incident_types.exists?(type.id)
  end

  test "the default cannot be disabled, and the reason says why" do
    severity = @workspace.incident_severities.find_by(is_default: true)
    skip "no default severity in this workspace" unless severity

    _, is_error, text = call_tool(Mcp::Tools::UPSERT_SEVERITY, {
      slug: severity.slug, enabled: false
    }, token: @admin_token)

    assert is_error
    assert_match(/default/, text)
    assert_nil severity.reload.deleted_at
  end

  test "deleting is refused while incidents still point at it" do
    severity = incidents(:active_critical_ws1).incident_severity

    _, is_error, text = call_tool(Mcp::Tools::DELETE_SEVERITY, {
      slug: severity.slug
    }, token: @admin_token)

    assert is_error
    assert_match(/cannot be deleted/, text)
    assert @workspace.incident_severities.exists?(severity.id)
  end

  test "deleting one nothing points at closes the gap it leaves" do
    type = @workspace.incident_types.create_in_list!(@workspace, { name: "Throwaway" })

    _, is_error = call_tool(Mcp::Tools::DELETE_INCIDENT_TYPE, { slug: type.slug }, token: @admin_token)

    assert_not is_error
    assert_not @workspace.incident_types.exists?(type.id)
    positions = @workspace.incident_types.ordered.pluck(:position)
    assert_equal (1..positions.size).to_a, positions
  end

  test "a key granted only incident reads cannot change a severity" do
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    )

    _, is_error = call_tool(Mcp::Tools::UPSERT_SEVERITY, { name: "Sneaky" }, token: token)

    assert is_error
    assert_nil @workspace.incident_severities.find_by(slug: "sneaky")
  end

  # An agent granted the resource reaches it. Whether to grant it is the
  # workspace's call, not the tool's.
  test "an agent granted severities can change them" do
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Config agent", slug: "config_agent",
      permissions: { Ability::Action::RESOURCE_SEVERITIES => %w[create update] }
    )

    _, is_error = call_tool(Mcp::Tools::UPSERT_SEVERITY, { name: "SEV4" }, token: token)

    assert_not is_error
    assert @workspace.incident_severities.exists?(slug: "sev4")
  end

  test "another workspace's severity is not reachable" do
    other = workspaces(:slack_workspace_two).incident_severities.first

    _, is_error = call_tool(Mcp::Tools::UPSERT_SEVERITY, { slug: other.slug, name: "Nope" }, token: @admin_token)

    assert is_error
  end

  private

  def rpc(method, params = {}, id: 1, token: @admin_token)
    post mcp_path,
         params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {}, token: @admin_token)
    result = rpc("tools/call", { name: name, arguments: arguments }, token: token).fetch("result")
    [ result["structuredContent"] || {}, result["isError"], result.dig("content", 0, "text") ]
  end
end
