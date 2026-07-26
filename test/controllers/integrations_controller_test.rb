require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :catalog_types, :catalog_entries

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "index lists connected integrations and the provider catalog" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry",
      settings: { "server_url" => "https://mcp.sentry.example/mcp" }
    )
    integration.integration_environments.create!
    integration.tools.create!(name: "issues.search", read_only: true, enabled: true)

    get integrations_url, headers: inertia_headers

    assert_response :success
    props = inertia_props
    assert_equal [ "Sentry" ], props["integrations"].map { |i| i["name"] }
    assert_equal "sentry.issues.search", props["integrations"].first["tools"].first["actionKey"]
    assert_includes props["providers"].map { |p| p["key"] }, "github"
    assert props["canManage"]
  end

  test "create connects, discovers tools, and records health" do
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([
      { "name" => "issues.search", "annotations" => { "readOnlyHint" => true } }
    ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    post integrations_url, params: {
      provider: "sentry", name: "Sentry",
      server_url: "https://mcp.sentry.example/mcp", authorization: "Bearer key"
    }

    assert_redirected_to integrations_path
    integration = @workspace.integrations.find_by!(provider: "sentry")
    assert_equal "Bearer key", integration.integration_environments.first.credentials_hash["authorization"]
    tool = integration.tools.find_by!(name: "issues.search")
    assert_not tool.enabled?, "discovered tools arrive disabled"
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, integration.integration_environments.first.health_status
  end

  test "an unreachable server still connects, marked failing" do
    Integrations::McpClient.any_instance.stubs(:tools_list).raises(Integrations::McpClient::Error, "down")

    post integrations_url, params: { provider: "custom_mcp", name: "Internal", server_url: "https://x/mcp" }

    assert_redirected_to integrations_path
    row = @workspace.integrations.find_by!(name: "Internal").integration_environments.first
    assert_equal IntegrationEnvironment::HEALTH_FAILING, row.health_status
  end

  test "toggling a tool mints its action; members cannot manage" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "github", name: "GitHub",
      settings: { "server_url" => "https://gh.example/mcp" }
    )
    tool = integration.tools.create!(name: "pr.list", read_only: true)

    patch toggle_tool_integration_url(integration), params: { tool_id: tool.id }
    assert tool.reload.enabled?
    assert Ability::Action.exists?(key: "github.pr.list")

    sign_in(users(:bob), @workspace)
    patch toggle_tool_integration_url(integration), params: { tool_id: tool.id }
    assert tool.reload.enabled?, "member toggle is rejected by require_admin!"
  end

  private

  def inertia_props
    JSON.parse(response.body)["props"]
  end

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
