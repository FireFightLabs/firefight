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

  test "oauth_start creates the pending connection and redirects to the provider's consent screen" do
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize?state=abc", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )

    get oauth_start_integrations_url(provider: "github")

    assert_redirected_to "https://auth.example/authorize?state=abc"
    integration = @workspace.integrations.find_by!(provider: "github")
    assert_equal "https://api.githubcopilot.com/mcp/", integration.server_url
    assert integration.integration_environments.one?
  end

  test "reconnecting a disconnected provider revives it instead of colliding on the slug" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "github", name: "GitHub",
      settings: { "server_url" => "https://api.githubcopilot.com/mcp/" }
    )
    integration.update!(deleted_at: Time.current)

    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )

    get oauth_start_integrations_url(provider: "github")

    assert_redirected_to "https://auth.example/authorize"
    assert_equal 1, @workspace.integrations.where(provider: "github").count
    assert_nil integration.reload.deleted_at
  end

  test "oauth callback with the right state stores tokens and discovers tools" do
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )
    get oauth_start_integrations_url(provider: "github")

    Integrations::OauthClient.expects(:exchange).returns(
      "access_token" => "at-1", "refresh_token" => "rt-1", "expires_at" => 1.hour.from_now.iso8601
    )
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "pr.list" } ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    get oauth_callback_integrations_url(state: "abc", code: "authcode")

    assert_redirected_to integrations_path
    row = @workspace.integrations.find_by!(provider: "github").integration_environments.first
    oauth = row.credentials_hash["oauth"]
    assert_equal "at-1", oauth["access_token"]
    assert_equal "cid", oauth["client_id"]
    assert row.integration.tools.exists?(name: "pr.list")
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
  end

  test "a GitHub App install id is captured for later server-to-server tokens" do
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://github.com/login/oauth/authorize", state: "abc",
      verifier: "ver", client_id: "Iv1.abc", token_endpoint: "https://github.com/login/oauth/access_token"
    )
    get oauth_start_integrations_url(provider: "github")

    Integrations::OauthClient.stubs(:exchange).returns("access_token" => "at-1")
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    get oauth_callback_integrations_url(state: "abc", code: "authcode", installation_id: "98765")

    row = @workspace.integrations.find_by!(provider: "github").integration_environments.first
    assert_equal "98765", row.base_config["installation_id"]
    assert_equal "at-1", row.credentials_hash.dig("oauth", "access_token")
  end

  test "oauth_start without a hosted server explains the token path" do
    get oauth_start_integrations_url(provider: "newrelic")

    assert_redirected_to integrations_path
    assert_match(/Connect with a token/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: "newrelic")
  end

  test "a configured provider app skips dynamic registration" do
    ENV["INTEGRATION_GITHUB_CLIENT_ID"] = "Iv1.abc"
    ENV["INTEGRATION_GITHUB_CLIENT_SECRET"] = "shh"

    Integrations::OauthClient.expects(:begin_flow)
      .with(has_entries(client_id: "Iv1.abc", client_secret: "shh"))
      .returns(authorize_url: "https://github.com/login/oauth/authorize", state: "abc",
               verifier: "ver", client_id: "Iv1.abc", client_secret: "shh",
               token_endpoint: "https://github.com/login/oauth/access_token")

    get oauth_start_integrations_url(provider: "github")

    assert_response :redirect
  ensure
    ENV.delete("INTEGRATION_GITHUB_CLIENT_ID")
    ENV.delete("INTEGRATION_GITHUB_CLIENT_SECRET")
  end

  test "a failed oauth start leaves no broken connection behind" do
    Integrations::OauthClient.stubs(:begin_flow).raises(
      Integrations::OauthClient::Error, "this provider needs a one-time OAuth app setup"
    )

    get oauth_start_integrations_url(provider: "github")

    assert_redirected_to integrations_path
    assert_match(/one-time OAuth app setup/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: "github"),
               "no credential-less row should be persisted when OAuth cannot start"
  end

  test "oauth callback rejects a mismatched state" do
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )
    get oauth_start_integrations_url(provider: "github")

    get oauth_callback_integrations_url(state: "WRONG", code: "authcode")

    assert_redirected_to integrations_path
    row = @workspace.integrations.find_by!(provider: "github").integration_environments.first
    assert_nil row.credentials_hash["oauth"]
  end

  test "expired oauth credentials refresh and persist on use" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "github", name: "GitHub",
      settings: { "server_url" => "https://gh.example/mcp" }
    )
    row = integration.integration_environments.create!(credentials: {
      "oauth" => { "access_token" => "stale", "refresh_token" => "rt-1",
                   "expires_at" => 1.minute.ago.iso8601,
                   "token_endpoint" => "https://auth.example/token",
                   "client_id" => "cid", "resource" => "https://gh.example/mcp" }
    }.to_json)

    Integrations::OauthClient.expects(:refresh).returns(
      "access_token" => "fresh", "refresh_token" => "rt-2", "expires_at" => 1.hour.from_now.iso8601
    )

    headers = Integrations::Credentials.headers_for(row)

    assert_equal "Bearer fresh", headers["Authorization"]
    persisted = row.reload.credentials_hash["oauth"]
    assert_equal "fresh", persisted["access_token"]
    assert_equal "rt-2", persisted["refresh_token"]
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
