require "test_helper"

# Firefight's own app with Linear is the one way to connect it, and reaches Linear's MCP server with the app's token.
# Jira's connects the tracker natively, beside its MCP server.
class IntegrationsAppConnectTest < ActionDispatch::IntegrationTest
  include IssueTrackerTestHelper

  LINEAR_SERVER = "https://mcp.linear.app/mcp".freeze
  SERVER_TOOLS = [
    { "name" => "save_issue", "description" => "Create or update an issue", "inputSchema" => { "type" => "object" } },
    { "name" => "get_issue", "description" => "Read an issue", "inputSchema" => { "type" => "object" }, "annotations" => { "readOnlyHint" => true } },
    { "name" => "list_issue_statuses", "description" => "A team's statuses", "inputSchema" => { "type" => "object" }, "annotations" => { "readOnlyHint" => true } },
    { "name" => "list_users", "description" => "People", "inputSchema" => { "type" => "object" }, "annotations" => { "readOnlyHint" => true } },
    { "name" => "list_projects", "description" => "Projects", "inputSchema" => { "type" => "object" } },
    { "name" => "save_comment", "description" => "Comment on an issue", "inputSchema" => { "type" => "object" } }
  ].freeze
  ACTOR = { "id" => "app-user", "app" => true, "organization" => { "id" => "org-1", "name" => "Acme", "urlKey" => "acme" }, "teams" => [ { "id" => "t" } ] }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    sign_in(users(:alice), @workspace)
    @env = %w[INTEGRATION_LINEAR_APP_CLIENT_ID INTEGRATION_LINEAR_APP_CLIENT_SECRET INTEGRATION_JIRA_APP_CLIENT_ID INTEGRATION_JIRA_APP_CLIENT_SECRET
              INTEGRATION_LINEAR_WEBHOOK_SECRET].index_with { |key| ENV[key] }
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"] = "lin-app"
    ENV["INTEGRATION_LINEAR_APP_CLIENT_SECRET"] = "lin-secret"
    ENV["INTEGRATION_JIRA_APP_CLIENT_ID"] = "atl-app"
    ENV["INTEGRATION_JIRA_APP_CLIENT_SECRET"] = "atl-secret"
    ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = "app-secret"
  end

  teardown { @env.each { |key, value| ENV[key] = value } }

  def start(provider, **params)
    get oauth_start_integrations_url(provider: provider, app: true, **params)
    URI.parse(response.location)
  end

  # Linear's token endpoint answers the code and every refresh, and its MCP server lists SERVER_TOOLS to whoever holds
  # the app's token. Each server the connection reached is kept with the headers it sent.
  def linear_answers(token: "lin_app_token")
    @tokens = []
    Integrations::OauthClient.stubs(:token_request).with { |endpoint, params, **| @tokens << [ endpoint, params ] }
                             .returns("access_token" => token, "refresh_token" => "rt", "expires_at" => 1.day.from_now.iso8601)
    @reached = []
    server = stub(ping: true, tools_list: SERVER_TOOLS)
    server.stubs(:call_tool).returns(json_answer("id" => "ENG-1", "title" => "Rotate", "url" => "https://linear.app/acme/issue/ENG-1/rotate"))
    Integrations::McpClient.stubs(:new).with { |server_url:, headers:, **| @reached << [ server_url, headers ] }.returns(server)
    Integrations::LinearApi.any_instance.stubs(:actor).returns(ACTOR)
  end

  def connect_linear(**params)
    state = Rack::Utils.parse_query(start("linear", **params).query)["state"]
    get oauth_callback_integrations_url(state: state, code: "code")
  end

  test "Linear's app installs as an app of its own that can be assigned and mentioned, with every scope Linear's tools need, never admin, and keeps nothing until the person comes back" do
    location = start("linear")
    query = Rack::Utils.parse_query(location.query)

    assert_equal "https://linear.app/oauth/authorize", "#{location.scheme}://#{location.host}#{location.path}"
    assert_equal [ "lin-app", "read,write,app:assignable,app:mentionable,customer:read,customer:write,initiative:read,initiative:write", "consent", "app", "S256" ],
                 query.values_at("client_id", "scope", "prompt", "actor", "code_challenge_method")
    assert_not_includes query["scope"].split(","), "admin"
    assert_not @workspace.integrations.exists?(provider: "linear")
  end

  test "Jira's app asks Atlassian's audience for its scopes" do
    query = Rack::Utils.parse_query(start("jira").query)

    assert_equal [ "atl-app", "api.atlassian.com", "read:jira-work write:jira-work read:jira-user manage:jira-webhook offline_access" ],
                 query.values_at("client_id", "audience", "scope")
    assert_nil query["code_challenge"]
  end

  test "coming back connects Linear's MCP server with the app's token, discovers every tool it lists switched on, and runs them with that token" do
    linear_answers
    connect_linear

    linear = @workspace.integrations.find_by!(slug: "linear")
    assert_equal [ Integration::KIND_MCP, LINEAR_SERVER, true ], [ linear.kind, linear.server_url, linear.through_app? ]
    assert_equal SERVER_TOOLS.pluck("name").sort, linear.tools.order(:name).pluck(:name)
    assert linear.tools.all?(&:enabled?)
    assert_equal [ [ LINEAR_SERVER, { "Authorization" => "Bearer lin_app_token" } ] ], @reached.uniq
    assert_equal [ "https://api.linear.app/oauth/token", "lin-app", "lin-secret" ], @tokens.sole.then { |endpoint, params| [ endpoint, params[:client_id], params[:client_secret] ] }

    row = linear.integration_environments.sole
    assert_equal [ "org-1", IntegrationEnvironment::HEALTH_HEALTHY ], [ row.installation_id, row.health_status ]

    result = Integrations::McpExecutor.call(tool: linear.tools.find_by!(name: "save_comment"), environment_row: row, arguments: { "issueId" => "ENG-1", "body" => "On it." })
    assert_equal "ENG-1", JSON.parse(result["content"].first["text"])["id"]
    assert_equal [ LINEAR_SERVER, { "Authorization" => "Bearer lin_app_token" } ], @reached.last
  end

  test "an app token close to expiry is refreshed at Linear's token endpoint with the app's own client" do
    linear_answers
    connect_linear
    row = @workspace.integrations.find_by!(slug: "linear").integration_environments.sole
    row.rotate_oauth!(row.oauth.merge("expires_at" => 10.seconds.from_now.iso8601))
    linear_answers(token: "lin_app_token_2")

    assert_equal({ "Authorization" => "Bearer lin_app_token_2" }, Integrations::Credentials.headers_for(row))
    endpoint, params = @tokens.uniq.sole
    assert_equal [ "https://api.linear.app/oauth/token", "refresh_token", "rt", "lin-app", "lin-secret" ],
                 [ endpoint, params[:grant_type], params[:refresh_token], params[:client_id], params[:client_secret] ]
  end

  test "the only tracker connected becomes the issue tracker, with its sync tools granted, and the toast says what is left to choose" do
    linear_answers
    connect_linear

    linear = @workspace.integrations.find_by!(slug: "linear")
    assert_equal "linear", @workspace.reload.issue_tracker
    assert_equal "Linear is connected. It is now this workspace's issue tracker, so incident items are kept in step with its issues. " \
                 "Choose the team new issues go to under Settings, Workspace.", flash[:notice]
    held = Ability::Resolver.resolve(SystemAgent.issue_sync, @workspace)
    assert linear.tools.where(name: Integrations::IssueTrackers::Linear::SYNC_TOOLS).all? { |tool| held.covers?(tool.action_key) }
    assert Ability::Invocation.exists?(principal_id: @alice.id, action_key: "workspace.update", source: AbilityGateway::SOURCE_ISSUE_SYNC)
  end

  test "with another tracker connected nothing is chosen, so the settings page keeps the choice" do
    jira = connect_tracker!(@workspace, provider: "jira", slug: "jira")
    linear_answers
    connect_linear

    assert_nil @workspace.reload.issue_tracker
    assert_equal "Linear is connected.", flash[:notice]
    assert jira.reload.operational?
  end

  test "a tracker already chosen stays chosen when its connection is made again" do
    linear_answers
    connect_linear
    @workspace.reload.update!(issue_tracker_target: { "team" => "ENG" })

    connect_linear

    assert_equal [ "linear", { "team" => "ENG" } ], [ @workspace.reload.issue_tracker, @workspace.issue_tracker_target ]
    assert_equal "Linear is connected.", flash[:notice]
  end

  test "an approval rule on workspace settings leaves the choice to the settings page and says so" do
    linear_answers
    Workspace.any_instance.stubs(:issue_tracker_choice_held?).returns(true)
    connect_linear

    assert_nil @workspace.reload.issue_tracker
    assert_equal "Linear is connected. #{IssueSyncService::CHOOSE_BY_HAND}", flash[:notice]
  end

  test "signing in again under a connection's name revives it with the app's token, keeping each tool as an admin left it" do
    signed_in = connect_tracker!(@workspace, provider: "linear", slug: "linear", name: "Linear")
    signed_in.tools.create!(name: "list_projects", description: "Projects", read_only: true, enabled: false, params_schema: {})
    linear_answers
    connect_linear

    assert_equal signed_in.id, @workspace.integrations.find_by!(slug: "linear").id
    assert_equal [ Integration::KIND_MCP, LINEAR_SERVER, true ], [ signed_in.reload.kind, signed_in.server_url, signed_in.through_app? ]
    assert_not signed_in.tools.find_by!(name: "list_projects").enabled?
    assert signed_in.tools.find_by!(name: "save_comment").enabled?
  end

  test "Jira's app still connects natively beside its MCP server, under its own name, and chooses nothing" do
    state = Rack::Utils.parse_query(start("jira").query)["state"]
    Integrations::OauthClient.expects(:exchange).with(has_entries(token_endpoint: "https://auth.atlassian.com/oauth/token", client_secret: "atl-secret", json: true))
                             .returns("access_token" => "at", "refresh_token" => "rt", "client_id" => "atl-app")
    Integrations::Packs::Jira.any_instance.stubs(:check_health!)

    get oauth_callback_integrations_url(state: state, code: "code")

    jira = @workspace.integrations.find_by!(slug: "jira_issue_sync")
    assert_equal [ Integration::KIND_NATIVE, "jira", true ], [ jira.kind, jira.provider, jira.through_app? ]
    assert_nil @workspace.reload.issue_tracker
    assert_equal "Jira issue sync is connected.", flash[:notice]
  end

  test "without the app registered on this install the dialog offers Linear's sign-in as before" do
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"] = nil
    Integrations::OauthFlow.expects(:begin).with { |provider, server_url:, **| provider.key == "linear" && server_url == LINEAR_SERVER }
                           .returns(authorize_url: "https://mcp.linear.app/authorize", state: "s", verifier: "v", client_id: "c", token_endpoint: "t")

    assert_nil IntegrationProviderSerializer.one(IntegrationProvider.find("linear"))[:app]
    get oauth_start_integrations_url(provider: "linear", app: true)
    assert_equal "mcp.linear.app", URI.parse(response.location).host
  end

  test "the dialog offers Linear's app in place of signing in, in the registry's words, and Jira's beside it under its label" do
    linear = IntegrationProviderSerializer.one(IntegrationProvider.find("linear"))[:app]
    jira = IntegrationProviderSerializer.one(IntegrationProvider.find("jira"))[:app]

    assert_equal [ true, "Linear", nil ], linear.values_at(:only, :connectionName, :label)
    assert_equal "Halon reads and updates issues as Firefight, keeps incident follow-ups in step and answers when someone assigns or mentions Firefight.",
                 linear[:description]
    assert_equal "A Linear admin approves Firefight's app on Linear's screen. No keys to copy.", linear[:consentNote]
    assert_equal [ false, "Jira issue sync", "Connect for issue sync", nil ], jira.values_at(:only, :connectionName, :label, :consentNote)
  end

  test "a provider connected from a URL ships the form's words from its pack, and others ship none" do
    words = IntegrationProviderSerializer.one(IntegrationProvider.find("postgresql"))[:connectionUrl]

    assert_match "postgresql://", words[:placeholder]
    assert_match "longer than #{Integrations::Packs::Postgres::Connection::STATEMENT_TIMEOUT_MS / 1000} seconds", words[:hint]
    assert_nil IntegrationProviderSerializer.one(IntegrationProvider.find("linear"))[:connectionUrl]
  end
end
