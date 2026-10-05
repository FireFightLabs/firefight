require "test_helper"

# Firefight's own app with Linear or Jira connects the tracker natively, beside its MCP server.
class IntegrationsAppConnectTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @env = %w[INTEGRATION_LINEAR_APP_CLIENT_ID INTEGRATION_LINEAR_APP_CLIENT_SECRET INTEGRATION_JIRA_APP_CLIENT_ID INTEGRATION_JIRA_APP_CLIENT_SECRET]
             .index_with { |key| ENV[key] }
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"] = "lin-app"
    ENV["INTEGRATION_LINEAR_APP_CLIENT_SECRET"] = "lin-secret"
    ENV["INTEGRATION_JIRA_APP_CLIENT_ID"] = "atl-app"
    ENV["INTEGRATION_JIRA_APP_CLIENT_SECRET"] = "atl-secret"
  end

  teardown { @env.each { |key, value| ENV[key] = value } }

  def start(provider)
    get oauth_start_integrations_url(provider: provider, kind: Integration::KIND_NATIVE)
    URI.parse(response.location)
  end

  test "Linear's app asks for its scopes with a code challenge and keeps nothing until the person comes back" do
    location = start("linear")
    query = Rack::Utils.parse_query(location.query)

    assert_equal "https://linear.app/oauth/authorize", "#{location.scheme}://#{location.host}#{location.path}"
    assert_equal [ "lin-app", "read,write,admin", "consent", "S256" ], query.values_at("client_id", "scope", "prompt", "code_challenge_method")
    assert_not @workspace.integrations.exists?(provider: "linear")
  end

  test "Jira's app asks Atlassian's audience for its scopes" do
    query = Rack::Utils.parse_query(start("jira").query)

    assert_equal [ "atl-app", "api.atlassian.com", "read:jira-work write:jira-work read:jira-user manage:jira-webhook offline_access" ],
                 query.values_at("client_id", "audience", "scope")
    assert_nil query["code_challenge"]
  end

  test "coming back connects a native connection beside the MCP one, with the pack's tools switched off" do
    mcp = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear", settings: { "server_url" => "https://mcp.linear.app/mcp" })
    state = Rack::Utils.parse_query(start("linear").query)["state"]
    Integrations::OauthClient.expects(:exchange).with(has_entries(token_endpoint: "https://api.linear.app/oauth/token", client_secret: "lin-secret",
                                                                  resource: nil, json: false))
                             .returns("access_token" => "at", "refresh_token" => "rt", "client_id" => "lin-app")
    Integrations::Packs::Linear.any_instance.stubs(:check_health!)

    get oauth_callback_integrations_url(state: state, code: "code")

    app = @workspace.integrations.find_by!(slug: "linear_issue_sync")
    assert_equal [ Integration::KIND_NATIVE, "linear" ], [ app.kind, app.provider ]
    assert_equal Integration::KIND_MCP, mcp.reload.kind
    assert_equal %w[get_issue list_issue_statuses list_users save_issue], app.tools.order(:name).pluck(:name)
    assert app.tools.none?(&:enabled?)
  end

  test "without the app registered on this install the dialog offers it nowhere" do
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"] = nil

    assert_nil IntegrationProviderSerializer.one(IntegrationProvider.find("linear"))[:app]
    assert_equal Integration::KIND_MCP, IntegrationProvider.find("linear").connect_kind(Integration::KIND_NATIVE)
  end
end
