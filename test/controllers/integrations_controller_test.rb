require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
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
    assert props["currentUserCan"]["integrations"]

    assert_equal Integration::KIND_MCP, props["integrations"].first["kind"]
    github = props["providers"].find { |p| p["key"] == "github" }
    assert_equal Integration::KIND_NATIVE, github["kind"]
    assert_equal IntegrationProvider.find("github").server_url, github["serverUrl"]
  end

  test "create connects, discovers tools, and records health" do
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([
      { "name" => "search_issues", "annotations" => { "readOnlyHint" => true } }
    ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    post integrations_url, params: {
      provider: "sentry", name: "Sentry",
      server_url: "https://mcp.sentry.example/mcp", authorization: "Bearer key"
    }

    assert_redirected_to integrations_path
    assert_equal "Sentry is connected.", flash[:notice]
    integration = @workspace.integrations.find_by!(provider: "sentry")
    assert_equal "Bearer key", integration.integration_environments.first.credentials_hash["authorization"]
    tool = integration.tools.find_by!(name: "search_issues")
    assert tool.enabled?, "discovered tools arrive switched on"
    assert_equal [ "Sentry: read", "Sentry: changes", "Sentry: everything" ], integration.permission_packs.order(:created_at).map(&:name)
    assert_includes integration.permission_packs.find_by!(pack: Ability::Role::PACK_READ).actions, tool.ability_action
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, integration.integration_environments.first.health_status
  end

  test "the token form sends a token in the header its provider's server reads it from" do
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    post integrations_url, params: {
      provider: "openstatus", name: "OpenStatus",
      server_url: IntegrationProvider.find("openstatus").server_url, authorization: "os_key"
    }

    assert_equal "OpenStatus is connected.", flash[:notice]
    row = @workspace.integrations.find_by!(provider: "openstatus").integration_environments.sole
    assert_equal({ "x-openstatus-key" => "os_key" }, Integrations::Credentials.headers_for(row))
    assert_nil row.credentials_hash["authorization"]
  end

  test "the token form builds the header from a provider's credential fields, and refuses one left empty" do
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    post integrations_url, params: {
      provider: "clickhouse", name: "ClickHouse", server_url: IntegrationProvider.find("clickhouse").server_url,
      token_fields: { key_id: " id-1 ", key_secret: "s3cret" }
    }
    assert_equal "ClickHouse is connected.", flash[:notice]
    row = @workspace.integrations.find_by!(provider: "clickhouse").integration_environments.sole
    assert_equal({ "Authorization" => "Basic #{Base64.strict_encode64('id-1:s3cret')}" }, Integrations::Credentials.headers_for(row))

    post integrations_url, params: {
      provider: "upstash", name: "Upstash", server_url: IntegrationProvider.find("upstash").server_url,
      token_fields: { email: "ops@example.com", api_key: "k3y" }
    }
    row = @workspace.integrations.find_by!(provider: "upstash").integration_environments.sole
    assert_equal({ "Authorization" => "Bearer ops@example.com:k3y" }, Integrations::Credentials.headers_for(row))

    assert_no_difference -> { @workspace.integrations.count } do
      post integrations_url, params: {
        provider: "neon", name: "Neon", server_url: IntegrationProvider.find("neon").server_url, token_fields: { api_key: " " }
      }
    end
    assert_equal "Fill in API key to connect with a token.", flash[:alert]
  end

  test "a header sent whole still connects a provider whose token form asks fields" do
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    post integrations_url, params: {
      provider: "neon", name: "Neon", server_url: IntegrationProvider.find("neon").server_url, authorization: "Bearer napi_key"
    }

    row = @workspace.integrations.find_by!(provider: "neon").integration_environments.sole
    assert_equal({ "Authorization" => "Bearer napi_key" }, Integrations::Credentials.headers_for(row))
  end

  test "a database connects from a URL, discovers its tools and records health, and the URL is never sent back" do
    Integrations::Packs::Postgres.stubs(:connection_refusal).returns(nil)
    Integrations::Packs::Postgres.any_instance.stubs(:check_health!).returns(true)

    post integrations_path, params: { provider: "postgresql", name: "Orders DB", connection_url: "postgresql://reader:s3cret@db.example.com/orders" }

    integration = @workspace.integrations.find_by!(name: "Orders DB")
    assert_equal Integration::KIND_NATIVE, integration.kind
    row = integration.integration_environments.sole
    assert_equal "postgresql://reader:s3cret@db.example.com/orders", row.credentials_hash[Integrations::Packs::Postgres::CONNECTION_URL]
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
    assert_includes integration.tools.pluck(:name), "run_query"

    get integrations_path, headers: inertia_headers
    assert_not_includes response.body, "s3cret"
  end

  test "Northflank connects with a token and a project, discovers its tools, and the token is never sent back" do
    Integrations::NorthflankApi.any_instance.stubs(:project).returns("data" => { "id" => "firefight" })

    post integrations_path, params: {
      provider: "northflank", name: "Northflank",
      credentials: { Integrations::Packs::Northflank::API_TOKEN => "nf-s3cret" }, fields: { Integrations::Packs::Northflank::PROJECT => [ "firefight" ] }
    }

    integration = @workspace.integrations.find_by!(name: "Northflank")
    row = integration.integration_environments.sole
    assert_equal({ Integrations::Packs::Northflank::API_TOKEN => "nf-s3cret" }, row.credentials_hash)
    assert_equal [ "firefight" ], Integrations::ConnectionSettings.of(row).field(Integrations::Packs::Northflank::PROJECT)
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
    assert_equal Integrations::Packs::Northflank.tool_definitions.map(&:name).sort, integration.tools.pluck(:name).sort

    get integrations_path, headers: inertia_headers
    assert_not_includes response.body, "nf-s3cret"
    provider = inertia_props["providers"].find { |candidate| candidate["key"] == "northflank" }
    assert_equal [ Integrations::Packs::Northflank::API_TOKEN ], provider["credentialFields"].map { |field| field["key"] }
    assert_equal [ Integrations::Packs::Northflank::PROJECT ], provider["connectFields"].map { |field| field["key"] }
    environment = inertia_props["integrations"].find { |each| each["provider"] == "northflank" }["environments"].sole
    assert_empty environment["settings"], "the projects are shown as a choice of their own"
    assert_equal [ "project", [ "firefight" ] ], environment["scopes"].values_at("key", "values")
  end

  test "GitLab connects with an access token and the address of a GitLab of its own, and discovers its tools" do
    Integrations::GitlabApi.any_instance.stubs(:get).returns([])

    post integrations_path, params: { provider: "gitlab", name: "GitLab", credentials: { Integrations::Packs::Gitlab::TOKEN => "glpat-s3cret" },
                                      fields: { Integrations::Packs::Gitlab::URL => "https://gitlab.example.com" } }

    integration = @workspace.integrations.find_by!(name: "GitLab")
    assert_equal Integration::KIND_NATIVE, integration.kind
    row = integration.integration_environments.sole
    settings = Integrations::ConnectionSettings.of(row)
    assert_equal [ "https://gitlab.example.com", "glpat-s3cret" ], [ settings.field(Integrations::Packs::Gitlab::URL), settings.credential(Integrations::Packs::Gitlab::TOKEN) ]
    assert_includes integration.tools.pluck(:name), "ci_status"

    get integrations_path, headers: inertia_headers
    assert_not_includes response.body, "glpat-s3cret"
    provider = inertia_props["providers"].find { |candidate| candidate["key"] == "gitlab" }
    assert_equal [ Integrations::Packs::Gitlab::TOKEN ], provider["credentialFields"].map { |field| field["key"] }
    assert_equal [ [ Integrations::Packs::Gitlab::URL, true ] ], provider["connectFields"].map { |field| [ field["key"], field["optional"] ] }
  end

  test "GitLab can still connect through its own MCP server with one-click OAuth, as before" do
    stub_begin_flow

    get oauth_start_integrations_url(provider: "gitlab", kind: Integration::KIND_MCP)

    assert_redirected_to "https://auth.example/authorize"
    Integrations::OauthClient.stubs(:exchange).returns("access_token" => "at-1", "refresh_token" => "rt-1", "expires_at" => 1.hour.from_now.iso8601, "client_id" => "cid")
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "get_merge_request" } ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    get oauth_callback_integrations_url(state: "abc", code: "authcode")

    integration = @workspace.integrations.find_by!(provider: "gitlab")
    assert_equal [ Integration::KIND_MCP, "https://gitlab.com/api/v4/mcp" ], [ integration.kind, integration.server_url ]
    assert integration.tools.exists?(name: "get_merge_request")
  end

  test "one-click connect for GitLab without asking for its MCP server is not offered, since it connects with a token" do
    get oauth_start_integrations_url(provider: "gitlab")

    assert_redirected_to integrations_path
    assert_equal "One-click connect is not configured for this integration on this install.", flash[:alert]
    assert_not @workspace.integrations.exists?(provider: "gitlab")
  end

  test "GitLab's MCP server can be connected with a token pasted by hand, as before" do
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "get_merge_request" } ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    post integrations_path, params: { provider: "gitlab", name: "GitLab", server_url: "https://gitlab.com/api/v4/mcp", authorization: "Bearer x" }

    assert_equal Integration::KIND_MCP, @workspace.integrations.find_by!(provider: "gitlab").kind
  end

  test "a Northflank token that is refused is said on the form and nothing is saved" do
    Integrations::NorthflankApi.any_instance.stubs(:project).raises(Integrations::NorthflankApi::Error, "Northflank answered 401: Unauthorized")

    post integrations_path, params: {
      provider: "northflank", name: "Northflank",
      credentials: { Integrations::Packs::Northflank::API_TOKEN => "wrong" }, fields: { Integrations::Packs::Northflank::PROJECT => "firefight" }
    }, headers: inertia_headers

    assert_nil @workspace.integrations.find_by(name: "Northflank")
  end

  test "the same name adds another environment to a database connection rather than a second connection" do
    Integrations::Packs::Postgres.stubs(:connection_refusal).returns(nil)
    Integrations::Packs::Postgres.any_instance.stubs(:check_health!).returns(true)
    staging = @workspace.environment_entries.first || skip("no environment entries in fixtures")

    post integrations_path, params: { provider: "postgresql", name: "Orders DB", connection_url: "postgresql://reader:a@db.example.com/orders" }
    post integrations_path, params: { provider: "postgresql", name: "Orders DB", connection_url: "postgresql://reader:b@staging.example.com/orders", environment_id: staging.id }

    assert_equal 2, @workspace.integrations.find_by!(name: "Orders DB").integration_environments.count
  end

  test "a database can still be connected through an MCP server the team runs" do
    Integrations::McpExecutor.stubs(:tool_definitions).returns([])
    Integrations::McpExecutor.stubs(:check_health!).returns(true)

    post integrations_path, params: { provider: "postgresql", name: "Orders MCP", server_url: "https://pg-mcp.example.com/mcp", authorization: "Bearer x" }

    integration = @workspace.integrations.find_by!(name: "Orders MCP")
    assert_equal [ Integration::KIND_MCP, "https://pg-mcp.example.com/mcp" ], [ integration.kind, integration.settings["server_url"] ]
  end

  test "a database URL that cannot be used is said on the form and nothing is saved" do
    assert_no_difference -> { @workspace.integrations.count } do
      post integrations_path, params: { provider: "postgresql", name: "Orders DB", connection_url: "postgresql://reader:secret@10.1.2.3/orders" },
                              headers: { "HTTP_REFERER" => integrations_url }
    end

    assert_redirected_to integrations_url
    assert_match "private network", session[:inertia_errors].to_h.with_indifferent_access[:connection].to_s
  end

  test "a connection cannot be called All, and the person is told why" do
    assert_no_difference -> { @workspace.integrations.count } do
      post integrations_url, params: { provider: "custom_mcp", name: "All", server_url: "https://x/mcp" }
    end

    assert_equal "All is kept for asking every connection at once. Pick a different name.", flash[:alert]
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
    assert_equal "pr.list on GitHub is on.", flash[:notice]
    assert Ability::Action.exists?(key: "github.pr.list")

    sign_in(users(:bob), @workspace)
    patch toggle_tool_integration_url(integration), params: { tool_id: tool.id }
    assert tool.reload.enabled?, "member toggle is rejected by require_admin!"
  end

  test "an admin marks a custom server's tool as a read and back, each said in a toast and in the activity log" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "custom_mcp", name: "Acme tools",
                                                  settings: { "server_url" => "https://tools.acme.example/mcp" })
    tool = integration.tools.create!(name: "query_logs", read_only: false, enabled: true)

    get integrations_url, headers: inertia_headers
    mark = inertia_props["integrations"].first["tools"].first["readMark"]
    assert_equal false, mark["marked"]
    assert_nil mark["blockedReason"]
    assert_match "Halon will call query_logs without asking", mark["words"]

    patch mark_tool_read_integration_url(integration), params: { tool_id: tool.id, read: true }
    assert_redirected_to integrations_path
    assert_equal "query_logs on Acme tools is marked as a read, so Halon calls it without asking.", flash[:notice]
    assert tool.reload.read_only?
    assert tool.marked_read?
    assert_equal Ability::Action::RISK_READ, tool.ability_action.risk_level
    logged = Ability::Invocation.where(workspace: @workspace, action_key: "integrations.update").order(:created_at).last
    assert_equal({ "tool" => "query_logs", "read" => true }, logged.params.slice("tool", "read"))

    patch mark_tool_read_integration_url(integration), params: { tool_id: tool.id, read: true }
    assert_equal "query_logs is already marked as a read.", flash[:alert]

    patch mark_tool_read_integration_url(integration), params: { tool_id: tool.id, read: false }
    assert_equal "query_logs on Acme tools is no longer marked as a read, so Halon asks before calling it.", flash[:notice]
    assert_not tool.reload.read_only?
  end

  test "a known provider's tools cannot be marked, so they are not offered, and a member cannot mark a custom server's" do
    sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.dev/mcp" })
    tool = sentry.tools.create!(name: "update_issue", read_only: false, enabled: true)

    patch mark_tool_read_integration_url(sentry), params: { tool_id: tool.id, read: true }
    assert_equal "Sentry's server is one Firefight knows, so its tools are marked as it says.", flash[:alert]
    assert_not tool.reload.read_only?
    get integrations_url, headers: inertia_headers
    assert_nil inertia_props["integrations"].first["tools"].first["readMark"]

    custom = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "custom_mcp", name: "Acme tools", settings: { "server_url" => "https://tools.acme.example/mcp" })
    mine = custom.tools.create!(name: "query_logs", read_only: false, enabled: true)
    sign_in(users(:bob), @workspace)
    patch mark_tool_read_integration_url(custom), params: { tool_id: mine.id, read: true }
    assert_not mine.reload.read_only?, "a member is refused integrations.update"
  end

  test "a tool the provider no longer offers cannot be switched on, by hand or in bulk" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "github", name: "GitHub",
      settings: { "server_url" => "https://gh.example/mcp" }
    )
    gone = integration.tools.create!(name: "pr.list", read_only: true, removed_at: Time.current)
    live = integration.tools.create!(name: "issues.list", read_only: true)

    patch toggle_tool_integration_url(integration), params: { tool_id: gone.id }
    assert_redirected_to integrations_path
    assert_equal gone.toggle_blocked_reason, flash[:alert]
    assert_not gone.reload.enabled?

    patch set_all_tools_integration_url(integration), params: { enabled: true }
    assert live.reload.enabled?
    assert_not gone.reload.enabled?

    get integrations_url, headers: inertia_headers
    tools = inertia_props["integrations"].first["tools"]
    assert_equal false, tools.find { |t| t["name"] == "pr.list" }["available"]
    assert_nil tools.find { |t| t["name"] == "issues.list" }["toggleBlockedReason"]
  end

  test "enabling every tool at once mints an action for each" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
      settings: { "server_url" => "https://mcp.linear.app/mcp" }
    )
    integration.tools.create!(name: "list_issues", read_only: true)
    integration.tools.create!(name: "create_issue", read_only: false)

    patch set_all_tools_integration_url(integration), params: { enabled: true }

    assert integration.tools.all?(&:enabled?)
    assert_equal "Every tool on Linear is on.", flash[:notice]
    assert Ability::Action.exists?(key: "linear.list_issues")
    assert Ability::Action.exists?(key: "linear.create_issue"),
           "bulk enable must mint actions, not just flip a column"

    patch set_all_tools_integration_url(integration), params: { enabled: false }
    assert integration.tools.reload.none?(&:enabled?)
    assert_equal "Every tool on Linear is off.", flash[:notice]
  end

  test "reads only turns the reads on and the writes back off" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
      settings: { "server_url" => "https://mcp.linear.app/mcp" }
    )
    read = integration.tools.create!(name: "list_issues", read_only: true)
    write = integration.tools.create!(name: "create_issue", read_only: false, enabled: true)

    patch set_all_tools_integration_url(integration), params: { enabled: true, reads_only: true }

    assert read.reload.enabled?
    assert_equal "Only the tools on Linear that read are on.", flash[:notice]
    assert_not write.reload.enabled?,
               "reads only states the target, so an already-enabled write is turned off"
  end

  test "members cannot bulk enable tools" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
      settings: { "server_url" => "https://mcp.linear.app/mcp" }
    )
    integration.tools.create!(name: "list_issues", read_only: true)
    sign_in(users(:bob), @workspace)

    patch set_all_tools_integration_url(integration), params: { enabled: true }

    assert integration.tools.reload.none?(&:enabled?)
  end

  test "oauth_start redirects to the provider without persisting anything" do
    stub_begin_flow

    get oauth_start_integrations_url(provider: "linear")

    assert_redirected_to "https://auth.example/authorize"
    assert_not @workspace.integrations.exists?(provider: "linear"),
               "abandoning the provider's screen must not leave a half-connected row"
  end

  test "reconnecting a disconnected provider revives it instead of colliding on the slug" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
      settings: { "server_url" => "https://mcp.linear.app/mcp" }
    )
    integration.update!(deleted_at: Time.current)

    complete_oauth_flow

    assert_equal 1, @workspace.integrations.where(provider: "linear").count
    assert_nil integration.reload.deleted_at
  end

  test "one provider backs several accounts, each with its own action keys" do
    complete_oauth_flow(name: "Linear Platform")
    complete_oauth_flow(name: "Linear Payments")

    slugs = @workspace.integrations.where(provider: "linear").order(:slug).pluck(:slug)
    assert_equal [ "linear_payments", "linear_platform" ], slugs

    keys = Integration::Tool.where(integration: @workspace.integrations).map(&:action_key)
    assert_includes keys, "linear_platform.pr.list"
    assert_includes keys, "linear_payments.pr.list"
  end

  test "connecting per environment gives one connection two credential sets" do
    production = catalog_entries(:production_env)
    development = catalog_entries(:development_env)

    complete_oauth_flow(start: { environment_id: production.id })
    complete_oauth_flow(start: { environment_id: development.id })

    integration = @workspace.integrations.find_by!(provider: "linear")
    assert_equal 1, @workspace.integrations.where(provider: "linear").count
    assert_equal [ development.id, production.id ].sort,
                 integration.integration_environments.pluck(:catalog_entry_id).sort
    assert_equal 1, integration.tools.where(name: "pr.list").count,
                 "environments share one tool and one action key; the grant's scope separates them"
  end

  test "a catalog entry that is not an environment is refused" do
    vendor = catalog_entries(:vendor_acme)

    complete_oauth_flow(start: { environment_id: vendor.id })

    row = @workspace.integrations.find_by!(provider: "linear").integration_environments.sole
    assert_nil row.catalog_entry_id, "an unverified environment id must not bind credentials"
  end

  test "an existing connection can be narrowed to one environment and widened back" do
    development = catalog_entries(:development_env)
    complete_oauth_flow
    row = @workspace.integrations.find_by!(provider: "linear").integration_environments.sole
    assert_nil row.catalog_entry_id

    patch retarget_environment_integration_url(row.integration),
          params: { environment_row_id: row.id, environment_id: development.id }
    assert_equal development.id, row.reload.catalog_entry_id
    assert_equal "#{row.integration.name} now answers for #{development.name}.", flash[:notice]

    patch retarget_environment_integration_url(row.integration),
          params: { environment_row_id: row.id, environment_id: "" }
    assert_nil row.reload.catalog_entry_id
    assert_equal "#{row.integration.name} now answers for every environment.", flash[:notice]
  end

  test "turning a connection off and on, and refreshing its tools, each say so" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
      settings: { "server_url" => "https://mcp.linear.app/mcp" }
    )

    patch toggle_integration_url(integration)
    assert_equal "Linear is off.", flash[:notice]
    patch toggle_integration_url(integration)
    assert_equal "Linear is on.", flash[:notice]

    Integrations::ConnectionRefresh.stubs(:run!).returns(true)
    post sync_integration_url(integration)
    assert_equal "Linear's tools were refreshed.", flash[:notice]

    Integrations::ConnectionRefresh.stubs(:run!).returns(false)
    post sync_integration_url(integration)
    assert_match "could not be reached", flash[:alert]
  end

  test "a PlanetScale service token's id is added and cleared from the connection's details, each said in a toast, and the token never sent back" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    row = integration.integration_environments.create!(credentials: IntegrationEnvironment.token_credentials("Bearer pscale_tkn_secret"))
    Integrations::ConnectionRefresh.expects(:run!).with(integration).twice.returns(true)

    patch edit_field_integration_url(integration), params: { environment_row_id: row.id, key: "service_token_id", value: " tok123 " }
    assert_equal "PlanetScale's service token ID was saved.", flash[:notice]
    assert_equal "tok123", row.reload.fields["service_token_id"]

    get integrations_url, headers: inertia_headers
    edits = inertia_props["integrations"].find { |each| each["id"] == integration.id }["environments"].sole["edits"]
    assert_equal [ { "key" => "service_token_id", "label" => "Service token ID", "value" => "tok123" } ],
                 edits.map { |edit| edit.slice("key", "label", "value") }
    assert_not_includes response.body, "pscale_tkn_secret"

    patch edit_field_integration_url(integration), params: { environment_row_id: row.id, key: "service_token_id", value: "" }
    assert_equal "PlanetScale's service token ID was cleared.", flash[:notice]
    assert_nil row.reload.fields["service_token_id"]
  end

  test "a field the provider does not let a person change after connecting is refused, and a member changes none" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    row = integration.integration_environments.create!

    patch edit_field_integration_url(integration), params: { environment_row_id: row.id, key: "server_url", value: "https://elsewhere.example" }
    assert_equal "PlanetScale has no such setting to change.", flash[:alert]

    sign_in(users(:bob), @workspace)
    patch edit_field_integration_url(integration), params: { environment_row_id: row.id, key: "service_token_id", value: "tok123" }
    assert_nil row.reload.fields["service_token_id"]
  end

  test "retargeting refuses an entry that is not one of this workspace's environments" do
    complete_oauth_flow
    row = @workspace.integrations.find_by!(provider: "linear").integration_environments.sole

    patch retarget_environment_integration_url(row.integration),
          params: { environment_row_id: row.id, environment_id: catalog_entries(:vendor_acme).id }

    assert_nil row.reload.catalog_entry_id, "an unverified id must not widen or rebind the connection"
    assert_match(/not available/, flash[:alert])
  end

  test "retargeting onto an environment the connection already covers is refused" do
    production = catalog_entries(:production_env)
    complete_oauth_flow(start: { environment_id: production.id })
    complete_oauth_flow(start: { environment_id: catalog_entries(:development_env).id })

    integration = @workspace.integrations.find_by!(provider: "linear")
    development_row = integration.integration_environments.find_by!(catalog_entry_id: catalog_entries(:development_env).id)

    patch retarget_environment_integration_url(integration),
          params: { environment_row_id: development_row.id, environment_id: production.id }

    assert_equal catalog_entries(:development_env).id, development_row.reload.catalog_entry_id
    assert_match(/already has credentials/, flash[:alert])
  end

  test "members cannot retarget an environment" do
    complete_oauth_flow
    row = @workspace.integrations.find_by!(provider: "linear").integration_environments.sole
    sign_in(users(:bob), @workspace)

    patch retarget_environment_integration_url(row.integration),
          params: { environment_row_id: row.id, environment_id: catalog_entries(:development_env).id }

    assert_nil row.reload.catalog_entry_id
  end

  test "a name belonging to another provider's connection cannot hijack it" do
    sentry = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry",
      settings: { "server_url" => "https://mcp.sentry.example/mcp" }
    )

    complete_oauth_flow(name: "Sentry")

    assert_equal "sentry", sentry.reload.provider
    assert_match(/already uses that name/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: "linear")
  end

  # The controller looks a connection up by the slug a name would derive to. If that drifts from
  # the model's rule, reconnecting silently creates a duplicate, so both use one helper.
  test "a name the slug rule has to rewrite still reuses one connection" do
    complete_oauth_flow(name: "Linear read-only")
    complete_oauth_flow(name: "Linear read-only")

    integration = @workspace.integrations.sole
    assert_equal "linear_read_only", integration.slug
    assert_equal Integration.slug_for("Linear read-only"), integration.slug
  end

  test "reconnecting under the default name reuses the connection" do
    complete_oauth_flow
    complete_oauth_flow

    assert_equal 1, @workspace.integrations.where(provider: "linear").count
  end

  test "connecting from a chat goes back to that chat and says so" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))

    complete_oauth_flow(start: { return_to: agent_chat_path(conversation) })

    assert_redirected_to agent_chat_path(conversation)
    assert_equal "Linear is connected.", flash[:notice]
  end

  test "a return address that is not a chat on this dashboard is ignored" do
    complete_oauth_flow(start: { return_to: "https://evil.example/phish" })
    assert_redirected_to integrations_path

    complete_oauth_flow(start: { return_to: "//evil.example" })
    assert_redirected_to integrations_path

    complete_oauth_flow(start: { return_to: settings_workspace_path })
    assert_redirected_to integrations_path
  end

  test "oauth callback with the right state stores tokens and discovers tools" do
    complete_oauth_flow

    assert_redirected_to integrations_path
    integration = @workspace.integrations.find_by!(provider: "linear")
    assert_equal "https://mcp.linear.app/mcp", integration.server_url

    row = integration.integration_environments.first
    assert_equal "at-1", row.oauth["access_token"]
    assert_equal "cid", row.oauth["client_id"]
    assert integration.tools.exists?(name: "pr.list")
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
  end

  test "connecting GitHub sends the browser to the App install screen without persisting anything" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")

    get oauth_start_integrations_url(provider: "github")

    assert_response :redirect
    assert_match %r{\Ahttps://github\.com/apps/firefight/installations/new\?state=}, response.location
    assert_not @workspace.integrations.exists?(provider: "github"),
               "abandoning the install screen must not leave a half-connected row"
  end

  test "the install callback stores the installation id and discovers the pack's tools" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_token")
    Integrations::GithubApp.stubs(:installation).returns(
      "account" => { "login" => "acme" }, "html_url" => "https://github.com/organizations/acme/settings/installations/98765",
      "permissions" => { "contents" => "read", "metadata" => "read" }, "suspended_at" => nil
    )
    Integrations::GithubApp.stubs(:get).with("/installation/repositories?per_page=1", token: "ghs_token").returns("total_count" => 3)
    Integrations::GithubApp.expects(:user_installation_ids).with(code: "user-code", redirect_uri: oauth_callback_integrations_url).returns([ "111", "98765" ])
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get oauth_callback_integrations_url(state: state, installation_id: "98765", code: "user-code")

    assert_redirected_to integrations_path
    integration = @workspace.integrations.find_by!(provider: "github")
    assert_equal Integration::KIND_NATIVE, integration.kind
    assert_nil integration.server_url

    row = integration.integration_environments.sole
    assert_equal "98765", row.base_config["installation_id"]
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
    assert_equal [ "acme", "https://github.com/organizations/acme/settings/installations/98765", "read" ],
                 [ row.installation_account, row.installation_page, row.installation_access["contents"] ], "connecting reads the installation's account, page and permissions"
    assert integration.tools.exists?(name: "pr_lookup")
    assert integration.tools.find_by!(name: "pr_lookup").enabled?, "pack tools arrive switched on like discovered ones"
  end

  test "an install callback without an installation id connects nothing" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get oauth_callback_integrations_url(state: state)

    assert_redirected_to integrations_path
    assert_match(/did not complete/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: "github")
  end

  test "an installation the person who came back cannot manage is refused and connects nothing" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")
    Integrations::GithubApp.stubs(:user_installation_ids).returns([ "111" ])
    Integrations::GithubApp.expects(:installation).never
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get oauth_callback_integrations_url(state: state, installation_id: "98765", code: "user-code")

    assert_redirected_to integrations_path
    assert_equal "That GitHub installation is not one your GitHub account can manage, so nothing was connected. Install the app on an account you manage, then connect again.",
                 flash[:alert]
    assert_not @workspace.integrations.exists?(provider: "github")
  end

  test "an install callback GitHub sent without signing the person in connects nothing and says what to turn on" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")
    Integrations::GithubApp.expects(:user_installation_ids).never
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get oauth_callback_integrations_url(state: state, installation_id: "98765")

    assert_redirected_to integrations_path
    assert_equal "GitHub did not say who installed the app, so Firefight could not check the installation is yours and connected nothing. " \
                 "Whoever runs this Firefight needs to turn on Request user authorization (OAuth) during installation in the GitHub App's settings, then connect again.",
                 flash[:alert]
    assert_not @workspace.integrations.exists?(provider: "github")
  end

  test "a sign-in GitHub would not confirm is refused with GitHub's words and connects nothing" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")
    Integrations::GithubApp.stubs(:user_installation_ids).raises(Integrations::GithubApp::Error, "GitHub did not accept the sign-in: The code passed is incorrect or expired.")
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get oauth_callback_integrations_url(state: state, installation_id: "98765", code: "stale")

    assert_redirected_to integrations_path
    assert_equal "GitHub could not confirm the installation is yours, so nothing was connected. GitHub did not accept the sign-in: The code passed is incorrect or expired. Try again.",
                 flash[:alert]
    assert_not @workspace.integrations.exists?(provider: "github")
  end

  test "a connection started in one workspace is refused when its callback comes back in another, and nothing is connected" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns(app_slug: "firefight", client_id: "Iv1.abc")
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    other = workspaces(:slack_workspace_two)
    sign_in(users(:alice), other)
    Integrations::GithubApp.expects(:user_installation_ids).never

    get oauth_callback_integrations_url(state: state, installation_id: "98765", code: "user-code")

    assert_redirected_to integrations_path
    assert_equal "This connection was started in another workspace, so nothing was connected. Start it again here.", flash[:alert]
    assert_not other.integrations.exists?(provider: "github")
    assert_not @workspace.integrations.exists?(provider: "github")
  end

  test "GitHub connect without an app slug configured explains itself" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns({})

    get oauth_start_integrations_url(provider: "github")

    assert_redirected_to integrations_path
    assert_match(/not configured/, flash[:alert])
  end

  # A hosted-server provider that needs code to connect is a design failure, so the registry alone must carry it.
  test "a registry provider with a hosted server needs no provider-specific code" do
    entry = IntegrationProvider.find("linear")

    assert_equal "https://mcp.linear.app/mcp", entry.server_url
    assert_empty IntegrationProvider.oauth_client("linear"),
                 "Linear registers dynamically, so it must need no pre-registered app"

    Integrations::OauthClient.expects(:begin_flow)
      .with(has_entries(server_url: entry.server_url, client_id: nil))
      .returns(authorize_url: "https://mcp.linear.app/authorize", state: "abc", verifier: "ver",
               client_id: "dyn", token_endpoint: "https://mcp.linear.app/token")

    get oauth_start_integrations_url(provider: "linear")

    assert_redirected_to "https://mcp.linear.app/authorize"
  end

  # ProviderMark falls back to a letter mark, so a missing logo degrades rather than breaks, but looks unfinished.
  test "every provider ships a logo" do
    missing = IntegrationProvider.all.reject do |provider|
      Rails.root.join("public/integrations/#{provider.key}.svg").exist?
    end

    assert_empty missing.map(&:key)
  end

  test "category taglines come from the registry, not the frontend" do
    get integrations_url, headers: inertia_headers

    props = inertia_props
    assert_equal "Issues", props["providers"].find { |p| p["key"] == "linear" }["category"]
    assert props["categories"]["Issues"].present?,
           "a provider in a new category must not need a code change to get its heading"
  end

  test "oauth_start without a hosted server explains the token path" do
    get oauth_start_integrations_url(provider: Integration::PROVIDER_CUSTOM_MCP)

    assert_redirected_to integrations_path
    assert_match(/Connect with a token/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: Integration::PROVIDER_CUSTOM_MCP)
  end

  test "a configured provider app skips dynamic registration" do
    ENV["INTEGRATION_DATADOG_CLIENT_ID"] = "dd-client"

    Integrations::OauthClient.expects(:begin_flow)
      .with(has_entries(client_id: "dd-client"))
      .returns(authorize_url: "https://auth.example/authorize", state: "abc",
               verifier: "ver", client_id: "dd-client",
               token_endpoint: "https://auth.example/token")

    get oauth_start_integrations_url(provider: "datadog")

    assert_response :redirect
  ensure
    ENV.delete("INTEGRATION_DATADOG_CLIENT_ID")
  end

  test "the client secret never reaches the browser session" do
    ENV["INTEGRATION_DATADOG_CLIENT_SECRET"] = "shh"
    stub_begin_flow

    get oauth_start_integrations_url(provider: "datadog")

    assert_not_includes session[:integration_oauth].to_s, "shh"
  ensure
    ENV.delete("INTEGRATION_DATADOG_CLIENT_SECRET")
  end

  test "a failed oauth start leaves no broken connection behind" do
    Integrations::OauthClient.stubs(:begin_flow).raises(
      Integrations::OauthClient::Error, "this provider needs a one-time OAuth app setup"
    )

    get oauth_start_integrations_url(provider: "linear")

    assert_redirected_to integrations_path
    assert_match(/one-time OAuth app setup/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: "linear"),
               "no credential-less row should be persisted when OAuth cannot start"
  end

  test "oauth callback rejects a mismatched state" do
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )
    get oauth_start_integrations_url(provider: "linear")

    get oauth_callback_integrations_url(state: "WRONG", code: "authcode")

    assert_redirected_to integrations_path
    assert_not @workspace.integrations.exists?(provider: "linear")
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
    persisted = row.reload.oauth
    assert_equal "fresh", persisted["access_token"]
    assert_equal "rt-2", persisted["refresh_token"]
  end

  test "connecting a native provider needs no server URL and reads tools from its pack" do
    native_entry = IntegrationProvider::Entry.new(
      key: "fakepack", name: "Fake Pack", category: "Custom", mark: "FP", color: "#000000",
      description: "Test pack", server_url: "", kind: Integration::KIND_NATIVE, source_links: IntegrationProvider::SOURCE_LINKS_FIREFIGHT,
      map: IntegrationProvider::MAP_NONE
    )
    IntegrationProvider.stubs(:find).with("fakepack").returns(native_entry)
    Integrations::NativePack.stubs(:for).with("fakepack").returns(FakeNativePack)

    post integrations_url, params: { provider: "fakepack", name: "Fake Pack" }

    assert_redirected_to integrations_path
    integration = @workspace.integrations.find_by!(provider: "fakepack")
    assert_equal Integration::KIND_NATIVE, integration.kind
    assert_nil integration.server_url

    tool = integration.tools.find_by!(name: "echo_text")
    assert tool.enabled?, "pack tools arrive switched on like discovered ones"
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY,
                 integration.integration_environments.first.health_status
  end

  test "every registry provider declares a known kind and native ones have a pack" do
    IntegrationProvider.all.each do |provider|
      assert_includes Integration::KINDS, provider.kind,
                      "provider '#{provider.key}' declares unknown kind '#{provider.kind}'"
      if provider.kind == Integration::KIND_NATIVE
        assert Integrations::NativePack.for(provider.key),
               "provider '#{provider.key}' is kind: native but has no registered pack"
      end
    end
  end

  private

  def live_toggle(name) = live_state(name)["toggle"]

  def live_state(name)
    get integrations_url, headers: inertia_headers
    inertia_props["integrations"].find { |each| each["name"] == name }["environments"].sole["liveUpdates"]
  end

  def stub_begin_flow
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )
  end

  # Walks start, the provider's screen and the callback, so tests assert on the connection the whole flow produces.
  def complete_oauth_flow(callback: {}, name: nil, start: {})
    stub_begin_flow
    get oauth_start_integrations_url({ provider: "linear" }.merge(name ? { name: name } : {}).merge(start))

    Integrations::OauthClient.stubs(:exchange).returns(
      "access_token" => "at-1", "refresh_token" => "rt-1",
      "expires_at" => 1.hour.from_now.iso8601, "client_id" => "cid"
    )
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "pr.list" } ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)

    get oauth_callback_integrations_url({ state: "abc", code: "authcode" }.merge(callback))
  end

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end

  test "a connection set up by hand shows its address, steps and live updates, and saving its signing secret turns them on" do
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "firefight.example.com"
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "livetest", name: "Live test", slug: "livetest")
    row = integration.integration_environments.create!
    row.give_map_events_token!

    get integrations_url, headers: inertia_headers
    live = inertia_props["integrations"].find { |each| each["id"] == integration.id }["environments"].sole["liveUpdates"]
    assert_equal false, live["on"]
    assert_equal "https://firefight.example.com/api/v1/map_events/#{row.map_events_token}", live["setup"]["address"]
    assert_equal LiveTestEvents.setup_steps, live["setup"]["steps"]
    assert_equal false, live["setup"]["secretSet"]

    patch map_events_secret_integration_url(integration), params: { environment_row_id: row.id, secret: "whsec" }

    assert_redirected_to integrations_path
    assert_equal "Signing secret saved. Changes Live test sends now reach the map.", flash[:notice]
    assert_equal "whsec", row.reload.map_events_secret
    assert row.live_updates.on
  ensure
    ENV["APP_HOST"] = previous
  end

  test "an empty secret, a connection not set up by hand and a member are each refused" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "livetest", name: "Live test", slug: "livetest")
    row = integration.integration_environments.create!

    patch map_events_secret_integration_url(integration), params: { environment_row_id: row.id, secret: "  " }
    assert_equal "Paste the signing secret Live test shows for its webhook.", flash[:alert]

    sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.example/mcp" })
    patch map_events_secret_integration_url(sentry), params: { environment_row_id: sentry.integration_environments.create!.id, secret: "whsec" }
    assert_equal "Sentry is not set up by hand to send its changes.", flash[:alert]

    sign_in(users(:bob), @workspace)
    patch map_events_secret_integration_url(integration), params: { environment_row_id: row.id, secret: "whsec" }
    assert_nil row.reload.map_events_secret
  end

  test "an admin turns live updates on and off for a connection that asked first, each with a toast" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "livehook", name: "Live hook", slug: "livehook")
    row = integration.integration_environments.create!
    LiveTestHook.asking = "Firefight's would be the account's only webhook."
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "firefight.example.com"
    Integrations::MapEvents.prepare!(row)

    get integrations_url, headers: inertia_headers
    state = inertia_props["integrations"].find { |each| each["name"] == "Live hook" }["environments"].sole["liveUpdates"]
    assert_equal [ false, { "turnsOn" => true, "words" => LiveTestHook.asking, "blockedReason" => nil, "subject" => "live updates" } ], [ state["on"], state["toggle"] ]

    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: true }
    assert_redirected_to integrations_path
    assert_equal "Live updates are on. Changes Live hook sends now reach the map.", flash[:notice]
    assert row.reload.live_updates.on

    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: true }
    assert_equal "Live updates are already on for Live hook.", flash[:alert]
    assert_equal false, live_toggle("Live hook")["turnsOn"]

    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: false }
    assert_equal "Live updates are off. Firefight removed its webhook from Live hook, and changes reach the map at each hourly sweep.", flash[:notice]
    assert_not row.reload.live_updates.on

    LiveTestHook.failure = "Live hook answered 500: down"
    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: true }
    assert_equal "Firefight could not follow Live hook's changes: Live hook answered 500: down. The map still updates at each hourly sweep.", flash[:alert]

    row.update_columns(enabled: false)
    assert_equal({ "turnsOn" => true, "words" => LiveTestHook.asking, "blockedReason" => "Live hook is switched off. Switch it on first.", "subject" => "live updates" },
                 live_toggle("Live hook"), "a switch that cannot be pressed is shown with why, never hidden")
  ensure
    LiveTestHook.asking = nil
    LiveTestHook.failure = nil
    ENV["APP_HOST"] = previous
  end

  test "Azure's instant updates are turned on beside its activity log, a refusal is said on its own until the next try, and turning them off keeps the log read" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure", slug: "azure")
    row = integration.integration_environments.create!
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "firefight.example.com"
    grid = Integrations::MapEventSources::Azure
    Integrations::MapEvents.prepare!(row)
    assert_nil row.reload.map_events_webhook_id, "Event Grid is never turned on without a person"

    live = live_state("Azure")
    assert_equal [ true, "every 5 minutes", { "line" => "Instant updates: off", "on" => false, "reason" => nil } ], live.values_at("on", "checkedEvery", "secondWay")
    assert_equal "instant updates", live["toggle"]["subject"]
    assert_equal "#{grid.turn_on_words} #{grid::CONFIRMATION}", live["toggle"]["words"]
    assert_match "reads Azure's activity log every 5 minutes", row.live_updates.reason

    refusal = format(grid::NO_ROLE, role: grid::GRID_ROLE, name: "Production")
    grid.stubs(:register).raises(Integrations::Error, refusal)
    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: true }
    assert_equal "Instant updates could not be turned on. #{refusal}", flash[:alert]
    assert_equal [ nil, nil, refusal ], row.reload.values_at(:map_events_refused_at, :map_events_error, :map_events_registration_error), "the activity log is not held back"
    live = live_state("Azure")
    assert live["on"], "a refused setup never says the activity log is off"
    assert_equal({ "line" => "Instant updates could not be turned on", "on" => false, "reason" => refusal }, live["secondWay"])
    Integrations::MapEvents.prepare!(row.reload)
    assert_equal refusal, row.reload.live_updates.second_way.reason, "the refusal stays until a person tries again"

    grid.stubs(:register).returns(Integrations::MapEventSource::Webhook.new(id: { "s" => "/x" }.to_json, secret: "k", scopes: [ "s" ]))
    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: true }
    assert_equal "Instant updates are on. Changes Azure sends now reach the map.", flash[:notice]
    assert_equal({ "line" => "Instant updates: on", "on" => true, "reason" => nil }, live_state("Azure")["secondWay"])

    assert_equal grid.turn_off_words, live_toggle("Azure")["words"]
    grid.expects(:remove).once
    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: false }
    assert_equal "Instant updates are off. Firefight removed its webhook from Azure and still checks for changes every 5 minutes.", flash[:notice]
    assert row.reload.live_updates.on, "the activity log is still read"
    assert_match "reads Azure's activity log every 5 minutes", row.live_updates.reason
  ensure
    ENV["APP_HOST"] = previous
  end

  test "Azure says why its instant updates could not be turned off in plain words" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure", slug: "azure")
    row = integration.integration_environments.create!(map_events_webhook_id: { "s" => "/x" }.to_json, map_events_confirmation: Integrations::MapEventSources::Azure::CONFIRMATION)
    refusal = format(Integrations::MapEventSources::Azure::NOT_REMOVED, name: "Production")
    Integrations::MapEventSources::Azure.stubs(:remove).raises(Integrations::Error, refusal)

    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: false }

    assert_equal "Instant updates could not be turned off. #{refusal}", flash[:alert]
    assert row.reload.map_events_webhook_id.present?
  end

  test "Convex's dialog says what turning on gains before what it costs" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "convex", name: "Convex", slug: "convex")
    integration.integration_environments.create!(map_events_confirmation: Integrations::MapEventSources::Convex::ONLY_STREAM)

    toggle = live_toggle("Convex")

    assert_equal "Firefight adds a webhook log stream to this Convex deployment, so a push, a pause or a settings change reaches Firefight " \
                 "within about a minute. Convex allows one webhook log stream per deployment, so your team could not add its own while this " \
                 "is on. Log streams need Convex's Pro plan.", toggle["words"]
    assert_equal "live updates", toggle["subject"]
  end

  test "Cloudflare's signing secret is made by Firefight, never rides in the page or the session, and is copied only by someone who may change the connection" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                  settings: { "server_url" => "https://mcp.cloudflare.example/mcp" })
    row = integration.integration_environments.create!
    row.give_map_events_token!

    live = live_state("Cloudflare")
    assert_equal({ "line" => "Pages notifications: waiting for setup", "on" => false, "reason" => nil }, live["secondWay"])
    assert_equal [ true, nil, Integrations::MapEventSources::Cloudflare.setup_steps ], live["setup"].values_at("makesSecret", "replaceSecret", "steps")
    assert_match "It does not change the map", live["setup"]["note"]
    post map_events_signing_secret_integration_url(integration), params: { environment_row_id: row.id }, as: :json
    assert_equal [ 422, "No signing secret is saved for Cloudflare. Make one first." ], [ response.status, response.parsed_body["error"] ]

    post map_events_secrets_integration_url(integration), params: { environment_row_id: row.id }

    assert_redirected_to integrations_path
    assert_equal "Cloudflare's signing secret was made. Copy it with Copy secret.", flash[:notice]
    secret = row.reload.map_events_secret
    assert_equal 64, secret.size
    assert_not_includes flash.to_hash.to_json, secret, "the secret never rides in the session"
    live = live_state("Cloudflare")
    assert_equal({ "line" => "Pages notifications: ready (secret saved)", "on" => true, "reason" => nil }, live["secondWay"])
    assert_match "stops working at once", live["setup"]["replaceSecret"]
    assert_not_includes response.body, secret, "the secret is never in the page"

    post map_events_signing_secret_integration_url(integration), params: { environment_row_id: row.id }, as: :json
    assert_response :success
    assert_equal({ "secret" => secret }, response.parsed_body)

    post map_events_secrets_integration_url(integration), params: { environment_row_id: row.id }
    assert_equal "Cloudflare's signing secret was replaced. The old one stopped working, so give each webhook the new one. Copy it with Copy secret.", flash[:notice]
    assert_not_equal secret, row.reload.map_events_secret

    patch map_events_secret_integration_url(integration), params: { environment_row_id: row.id, secret: "chosen-before" }
    assert_equal "Signing secret saved. #{Integrations::MapEventSources::Cloudflare.deliveries_words}", flash[:notice]
    assert_equal "chosen-before", row.reload.map_events_secret, "a secret a person chose before is still accepted"

    sign_in(users(:bob), @workspace)
    post map_events_signing_secret_integration_url(integration), params: { environment_row_id: row.id }, as: :json
    assert_not_includes response.body, "chosen-before", "a member cannot copy it"
    post map_events_secrets_integration_url(integration), params: { environment_row_id: row.id }
    assert_equal "chosen-before", row.reload.map_events_secret, "nor replace it"
  end

  test "a provider whose secret is pasted from it is never given one Firefight made" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "livetest", name: "Live test", slug: "livetest")
    row = integration.integration_environments.create!

    post map_events_secrets_integration_url(integration), params: { environment_row_id: row.id }

    assert_equal "Firefight does not make a signing secret for Live test.", flash[:alert]
    assert_nil row.reload.map_events_secret
    row.update!(map_events_secret: "pasted")
    post map_events_signing_secret_integration_url(integration), params: { environment_row_id: row.id }, as: :json
    assert_equal [ 422, "Firefight does not make a signing secret for Live test." ], [ response.status, response.parsed_body["error"] ]
  end

  test "a member cannot turn live updates on" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "livehook", name: "Live hook", slug: "livehook")
    row = integration.integration_environments.create!
    sign_in(users(:bob), @workspace)

    patch live_updates_integration_url(integration), params: { environment_row_id: row.id, on: true }

    assert_nil row.reload.map_events_webhook_id
  end

  test "an admin saves the paths Halon may not change, the details stay open and a toast says what was saved" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    details = integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)

    patch protected_paths_integration_url(integration), params: { paths: [ ".github/workflows/", "*.lock" ] }

    assert_redirected_to details
    assert_equal [ ".github/workflows/", "*.lock" ], integration.reload.protected_paths
    assert_equal "Saved. Halon may not change .github/workflows/ and *.lock in GitHub's repositories.", flash[:notice]

    patch protected_paths_integration_url(integration), params: { paths: [] }

    assert_equal [], integration.reload.protected_paths
    assert_equal "Saved. Halon may change any file in GitHub's repositories. Every change arrives as a pull request for review.", flash[:notice]
  end

  test "a path that cannot be read stays on the form with why, and the list is left as it was" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    integration.protect_paths!([ ".github/" ])

    patch protected_paths_integration_url(integration), params: { paths: [ "../secrets" ] }

    assert_redirected_to integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)
    assert_equal({ "paths" => "../secrets reaches outside the repository. Give a path inside it, such as infra/prod/" }, session[:inertia_errors].stringify_keys)
    assert_equal [ ".github/" ], integration.reload.protected_paths
  end

  test "the list shows for a code host only, and only an admin changes it" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    github.protect_paths!([ "infra/prod/**" ])
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.example/mcp" })

    get integrations_url, headers: inertia_headers

    by_name = inertia_props["integrations"].index_by { |integration| integration["name"] }
    assert_equal [ "infra/prod/**" ], by_name["GitHub"]["protectedPaths"]
    assert_nil by_name["Sentry"]["protectedPaths"]

    sign_in(users(:bob), @workspace)
    patch protected_paths_integration_url(github), params: { paths: [] }

    assert_equal [ "infra/prod/**" ], github.reload.protected_paths
  end

  test "connecting the same account again keeps its list" do
    Integrations::Credentials.stubs(:refusal).returns(nil)
    Integrations::ConnectionRefresh.stubs(:run!)
    post integrations_url, params: { provider: "gitlab", name: "GitLab", credentials: { token: "glpat-one" } }
    integration = @workspace.integrations.find_by!(slug: "gitlab")
    integration.protect_paths!([ ".gitlab-ci.yml" ])

    post integrations_url, params: { provider: "gitlab", name: "GitLab", credentials: { token: "glpat-two" } }

    assert_equal integration, @workspace.integrations.find_by!(slug: "gitlab")
    assert_equal [ ".gitlab-ci.yml" ], integration.reload.protected_paths
  end
end
