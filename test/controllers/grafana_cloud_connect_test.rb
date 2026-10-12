require "test_helper"

# Grafana Cloud's hosted MCP server takes only a sign-in, made per stack, through the same one-click connect every
# OAuth provider uses. A Grafana a team runs itself is still connected with its server's address and a token.
class GrafanaCloudConnectTest < ActionDispatch::IntegrationTest
  STACK_SERVER = "https://mcp.grafana.com/mcp/mystack.grafana.net".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    ApplicationController.any_instance.stubs(:current_user).returns(users(:alice))
    ApplicationController.any_instance.stubs(:current_workspace).returns(@workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "list_datasources", "annotations" => { "readOnlyHint" => true } } ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)
    Integrations::HealthProbes::Grafana.any_instance.stubs(:check!).returns(nil)
  end

  def start(stack: "mystack.grafana.net", name: nil)
    Integrations::OauthClient.expects(:begin_flow).with(has_entries(server_url: STACK_SERVER, scopes: [ "grafana:read" ])).returns(
      authorize_url: "https://mcp.grafana.com/mcp/oauth/authorize?grafana_url=https%3A%2F%2Fmystack.grafana.net&state=abc", state: "abc",
      verifier: "ver", client_id: "dcr-client", token_endpoint: "https://mcp.grafana.com/mcp/oauth/token"
    )
    get oauth_start_integrations_url({ provider: "grafana", fields: { stack: stack } }.merge(name ? { name: name } : {}))
  end

  def come_back(access_token: "at-1")
    Integrations::OauthClient.stubs(:exchange).returns(
      "access_token" => access_token, "refresh_token" => "rt-1", "expires_at" => 1.hour.from_now.iso8601,
      "client_id" => "dcr-client", "token_endpoint" => "https://mcp.grafana.com/mcp/oauth/token", "resource" => STACK_SERVER
    )
    get oauth_callback_integrations_url(state: "abc", code: "authcode")
  end

  test "signing in asks the stack's hosted server for reads alone, and keeps nothing until Grafana sends the person back" do
    start

    assert_redirected_to "https://mcp.grafana.com/mcp/oauth/authorize?grafana_url=https%3A%2F%2Fmystack.grafana.net&state=abc"
    assert_not @workspace.integrations.exists?(provider: "grafana")
  end

  test "a stack typed with https:// or without one is refused on the form, before leaving for Grafana" do
    Integrations::OauthClient.expects(:begin_flow).never

    get oauth_start_integrations_url(provider: "grafana", fields: { stack: "https://mystack.grafana.net" })
    assert_equal "Stack address can hold only a stack's address, such as mystack.grafana.net, without https:// or a path.", flash[:alert]

    get oauth_start_integrations_url(provider: "grafana")
    assert_equal "Stack address is required.", flash[:alert]
  end

  test "coming back signed in connects the stack, keeps the tokens encrypted and says so" do
    start
    come_back

    assert_equal "Grafana is connected.", flash[:notice]
    integration = @workspace.integrations.find_by!(provider: "grafana")
    assert_equal STACK_SERVER, integration.server_url
    assert_equal({ "stack" => "mystack.grafana.net" }, integration.address_fields)
    row = integration.integration_environments.sole
    assert_equal "at-1", row.oauth["access_token"]
    assert_not_includes row.read_attribute_before_type_cast(:credentials).to_s, "at-1", "the tokens are stored encrypted"
    assert_equal "Bearer at-1", Integrations::Credentials.headers_for(row)["Authorization"]
    assert_equal "https://mystack.grafana.net", Integrations::HealthProbes::Grafana.address(Integrations::ConnectionSettings.of(row))
  end

  test "a sign-in Grafana no longer refreshes fails the connection with how to sign in again, and signing in again under the same name replaces its tokens" do
    start
    come_back
    integration = @workspace.integrations.find_by!(provider: "grafana")
    row = integration.integration_environments.sole
    row.rotate_oauth!(row.oauth.merge("expires_at" => 1.minute.ago.iso8601))
    Integrations::OauthClient.stubs(:refresh).raises(Integrations::OauthClient::SignInEnded, "refresh token expired")

    assert_not Integrations::HealthCheckService.check!(row)
    assert_equal "The sign-in to Grafana has ended, so Firefight can no longer reach it. Open its details, choose Add connection and sign in again " \
                 "under the name Grafana.", row.reload.health_error
    get integrations_url, headers: inertia_headers
    assert_equal "failing", inertia_props["integrations"].find { |each| each["provider"] == "grafana" }["environments"].sole["healthStatus"]

    Integrations::OauthClient.unstub(:refresh)
    start
    come_back(access_token: "at-2")

    assert_equal "Grafana is connected.", flash[:notice]
    assert_equal 1, @workspace.integrations.where(provider: "grafana").count
    assert_equal "at-2", row.reload.oauth["access_token"]
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
  end

  test "a Grafana a team runs itself still connects with its server's address and a token" do
    post integrations_path, params: { provider: "grafana", name: "Grafana on prem", server_url: "https://mcp-grafana.acme.example/mcp", authorization: "Bearer glsa_x" }

    assert_equal "Grafana on prem is connected.", flash[:notice]
    integration = @workspace.integrations.find_by!(provider: "grafana")
    assert_equal "https://mcp-grafana.acme.example/mcp", integration.server_url
    assert_equal({ "Authorization" => "Bearer glsa_x" }, Integrations::Credentials.headers_for(integration.integration_environments.sole))
  end

  test "disconnecting says so" do
    start
    come_back
    integration = @workspace.integrations.find_by!(provider: "grafana")

    delete integration_url(integration)

    assert_equal "Disconnected Grafana.", flash[:notice]
  end
end
