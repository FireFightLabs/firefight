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

    assert_equal Integration::KIND_MCP, props["integrations"].first["kind"]
    github = props["providers"].find { |p| p["key"] == "github" }
    assert_equal Integration::KIND_NATIVE, github["kind"]
    assert_equal IntegrationProvider.find("github").server_url, github["serverUrl"]
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
    assert Ability::Action.exists?(key: "linear.list_issues")
    assert Ability::Action.exists?(key: "linear.create_issue"),
           "bulk enable must mint actions, not just flip a column"

    patch set_all_tools_integration_url(integration), params: { enabled: false }
    assert integration.tools.reload.none?(&:enabled?)
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

    patch retarget_environment_integration_url(row.integration),
          params: { environment_row_id: row.id, environment_id: "" }
    assert_nil row.reload.catalog_entry_id
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

  # The controller looks a connection up by the slug a name *would* derive to.
  # If that rule ever drifts from the model's, reconnecting silently creates a
  # duplicate instead of finding the row, so pin them to the same helper.
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
    get oauth_start_integrations_url(provider: "github")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get oauth_callback_integrations_url(state: state, installation_id: "98765")

    assert_redirected_to integrations_path
    integration = @workspace.integrations.find_by!(provider: "github")
    assert_equal Integration::KIND_NATIVE, integration.kind
    assert_nil integration.server_url

    row = integration.integration_environments.sole
    assert_equal "98765", row.base_config["installation_id"]
    assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.health_status
    assert integration.tools.exists?(name: "pr_lookup")
    assert_not integration.tools.find_by!(name: "pr_lookup").enabled?,
               "pack tools arrive disabled like discovered ones"
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

  test "GitHub connect without an app slug configured explains itself" do
    IntegrationProvider.stubs(:oauth_client).with("github").returns({})

    get oauth_start_integrations_url(provider: "github")

    assert_redirected_to integrations_path
    assert_match(/not configured/, flash[:alert])
  end

  # Every provider with a hosted server must be connectable through the
  # generic flow. A provider that needs code to connect is a design failure,
  # not a special case, so this asserts the registry alone carries it.
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

  # ProviderMark falls back to the letter mark, so a missing logo degrades
  # rather than breaks. It still looks unfinished next to thirteen that have one.
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
    get oauth_start_integrations_url(provider: "newrelic")

    assert_redirected_to integrations_path
    assert_match(/Connect with a token/, flash[:alert])
    assert_not @workspace.integrations.exists?(provider: "newrelic")
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
      description: "Test pack", server_url: "", kind: Integration::KIND_NATIVE
    )
    IntegrationProvider.stubs(:find).with("fakepack").returns(native_entry)
    Integrations::NativePack.stubs(:for).with("fakepack").returns(FakeNativePack)

    post integrations_url, params: { provider: "fakepack", name: "Fake Pack" }

    assert_redirected_to integrations_path
    integration = @workspace.integrations.find_by!(provider: "fakepack")
    assert_equal Integration::KIND_NATIVE, integration.kind
    assert_nil integration.server_url

    tool = integration.tools.find_by!(name: "echo_text")
    assert_not tool.enabled?, "pack tools arrive disabled like discovered ones"
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

  def stub_begin_flow
    Integrations::OauthClient.stubs(:begin_flow).returns(
      authorize_url: "https://auth.example/authorize", state: "abc",
      verifier: "ver", client_id: "cid", token_endpoint: "https://auth.example/token"
    )
  end

  # Walks the browser through start, the provider's screen, and the callback,
  # so tests assert on the connection the whole flow produces.
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
end
