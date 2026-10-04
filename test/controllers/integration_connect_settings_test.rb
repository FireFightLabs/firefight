require "test_helper"

# Regions and connect fields, on every way a connection is made: one-click OAuth, a pasted server address, and
# credentials a pack asks for.
class IntegrationConnectSettingsTest < ActionDispatch::IntegrationTest
  EU1 = "https://mcp.datadoghq.eu/v1/mcp".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    ApplicationController.any_instance.stubs(:current_user).returns(users(:alice))
    ApplicationController.any_instance.stubs(:current_workspace).returns(@workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
    Integrations::McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "search_datadog_logs" } ])
    Integrations::McpClient.any_instance.stubs(:ping).returns(true)
  end

  test "the chosen region's server is the one OAuth asks a token for and the connection calls, and the connection keeps its region" do
    Integrations::OauthClient.expects(:begin_flow).with(has_entries(server_url: EU1)).returns(flow)
    get oauth_start_integrations_url(provider: "datadog", region: "eu1", environment_id: catalog_entries(:production_env).id)

    Integrations::OauthClient.expects(:exchange).with(has_entries(resource: EU1)).returns("access_token" => "at")
    get oauth_callback_integrations_url(state: "abc", code: "c")

    datadog = @workspace.integrations.find_by!(provider: "datadog")
    assert_equal [ EU1, "eu1" ], [ datadog.server_url, datadog.region_key ]
    assert_equal "https://app.datadoghq.eu", Integrations::ConnectionSettings.of(datadog.integration_environments.sole).region.site
  end

  test "without a region a provider's connection reaches its first one" do
    Integrations::OauthClient.expects(:begin_flow).with(has_entries(server_url: "https://mcp.datadoghq.com/v1/mcp")).returns(flow)

    get oauth_start_integrations_url(provider: "datadog")

    assert_equal "us1", session[:integration_oauth]["region"]
  end

  test "a region the provider does not have is refused before the provider's screen opens" do
    Integrations::OauthClient.expects(:begin_flow).never

    get oauth_start_integrations_url(provider: "datadog", region: "mars1")

    assert_redirected_to integrations_path
    assert_match "Datadog has no region called mars1", flash[:alert]
    assert_nil session[:integration_oauth]
  end

  test "another environment cannot move a connection to another region, and is told to name its own" do
    connect_datadog(region: "eu1", environment: catalog_entries(:production_env))

    Integrations::OauthClient.stubs(:begin_flow).returns(flow)
    Integrations::OauthClient.stubs(:exchange).returns("access_token" => "at")
    get oauth_start_integrations_url(provider: "datadog", region: "us1", environment_id: catalog_entries(:development_env).id)
    get oauth_callback_integrations_url(state: "abc", code: "c")

    assert_match "Datadog reaches EU1 (app.datadoghq.eu) for its other environments", flash[:alert]
    datadog = @workspace.integrations.find_by!(provider: "datadog")
    assert_equal [ EU1, 1 ], [ datadog.server_url, datadog.integration_environments.count ]
  end

  test "a connection made before regions keeps calling the server it was made with when it is authorized again" do
    unstable = "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp"
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => unstable })
    datadog.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)

    Integrations::OauthClient.expects(:begin_flow).with(has_entries(server_url: unstable)).returns(flow)
    get oauth_start_integrations_url(provider: "datadog", environment_id: catalog_entries(:development_env).id)
    Integrations::OauthClient.stubs(:exchange).returns("access_token" => "at")
    get oauth_callback_integrations_url(state: "abc", code: "c")

    assert_equal [ unstable, "us1", 2 ], [ datadog.reload.server_url, datadog.region.key, datadog.integration_environments.count ]
  end

  test "fields that are part of the server's address shape it, in order, and the others are kept on the environment" do
    with_acme do
      Integrations::OauthClient.expects(:begin_flow).with(has_entries(server_url: "https://mcp.acme.example/mcp/acme-co/web")).returns(flow)
      get oauth_start_integrations_url(provider: "acme", fields: { organization: " acme-co ", project: "web", account: "42", other: "x" })
      Integrations::OauthClient.expects(:exchange).with(has_entries(resource: "https://mcp.acme.example/mcp/acme-co/web")).returns("access_token" => "at")
      get oauth_callback_integrations_url(state: "abc", code: "c")

      acme = @workspace.integrations.find_by!(provider: "acme")
      row = acme.integration_environments.sole
      assert_equal "https://mcp.acme.example/mcp/acme-co/web", acme.server_url
      assert_equal({ "organization" => "acme-co", "project" => "web" }, acme.path_fields)
      assert_equal({ "account" => "42" }, row.fields)
      settings = Integrations::ConnectionSettings.of(row)
      assert_equal %w[acme-co 42], [ settings.field("organization"), settings.field(:account) ]

      get integrations_url, headers: inertia_headers
      shown = inertia_props["integrations"].find { |integration| integration["provider"] == "acme" }["environments"].sole["settings"]
      assert_equal [ { "label" => "Region", "value" => "US" }, { "label" => "Organization", "value" => "acme-co" },
                     { "label" => "Project", "value" => "web" }, { "label" => "Account", "value" => "42" } ], shown
    end
  end

  test "an optional part of the address left empty ends the address there" do
    with_acme do
      Integrations::OauthClient.expects(:begin_flow).with(has_entries(server_url: "https://mcp.acme.example/mcp/acme-co")).returns(flow)

      get oauth_start_integrations_url(provider: "acme", region: "us", fields: { organization: "acme-co", account: "42" })

      assert_equal "https://mcp.acme.example/mcp/acme-co", session[:integration_oauth]["server_url"]
    end
  end

  test "a field that is required, a number or part of the address is checked before the provider's screen opens" do
    with_acme do
      Integrations::OauthClient.expects(:begin_flow).never

      get oauth_start_integrations_url(provider: "acme", fields: { account: "42" })
      assert_equal "Organization is required.", flash[:alert]

      get oauth_start_integrations_url(provider: "acme", fields: { organization: "acme/co", account: "42" })
      assert_equal "Organization can hold only letters, numbers, dots, dashes and underscores, starting with a letter or number.", flash[:alert]

      get oauth_start_integrations_url(provider: "acme", fields: { organization: "acme", account: "forty" })
      assert_equal "Account must be a number.", flash[:alert]
    end
  end

  test "the form for a pasted server address asks only the fields that are not part of it, and keeps them on the environment" do
    with_acme do
      post integrations_url, params: { provider: "acme", name: "Acme", server_url: "https://mcp.acme.example/mcp/acme-co", fields: { account: "7" } }

      acme = @workspace.integrations.find_by!(provider: "acme")
      assert_equal [ "https://mcp.acme.example/mcp/acme-co", { "account" => "7" } ], [ acme.server_url, acme.integration_environments.sole.fields ]

      post integrations_url, params: { provider: "acme", name: "Acme two", server_url: "https://mcp.acme.example/mcp/acme-co" }
      assert_equal "Account is required.", flash[:alert]
      assert_not @workspace.integrations.exists?(name: "Acme two")
    end
  end

  test "credentials a pack checks are checked in the chosen region" do
    Integrations::Credentials.expects(:refusal).with("northflank", { "api_token" => "nf", "project" => "shop" }, region: nil, fields: {}).returns("Northflank refused this token.")

    post integrations_url, params: { provider: "northflank", name: "Northflank", credentials: { api_token: "nf", project: "shop" } }

    assert_equal "Northflank refused this token.", session[:inertia_errors].to_h.with_indifferent_access[:connection]
  end

  test "a pack's form asks its connect fields too, a list where a field holds several, checked with the credentials and kept on the environment" do
    northflank = IntegrationProvider.find("northflank")
    regions = IntegrationProvider::ConnectField.new(key: "regions", label: "Regions", hint: "Where it runs.", multiple: true,
                                                    options: [ { "value" => "us-east-1", "label" => "US East (N. Virginia)" },
                                                               { "value" => "eu-west-1", "label" => "Europe (Ireland)" } ])
    entries = IntegrationProvider.all.map { |entry| entry.key == "northflank" ? northflank.with(connect_fields: [ regions ]) : entry }
    IntegrationProvider.stubs(:all).returns(entries)
    Integrations::Credentials.expects(:refusal).with("northflank", { "api_token" => "nf", "project" => "shop" }, region: nil,
                                                                   fields: { "regions" => %w[us-east-1 eu-west-1] }).returns(nil)
    Integrations::Credentials.expects(:store!)
    Integrations::ConnectionRefresh.stubs(:run!)

    post integrations_url, params: { provider: "northflank", name: "Northflank", credentials: { api_token: "nf", project: "shop" },
                                     fields: { regions: [ "us-east-1", " eu-west-1 ", "" ] } }

    row = @workspace.integrations.find_by!(provider: "northflank").integration_environments.sole
    assert_equal %w[us-east-1 eu-west-1], Integrations::ConnectionSettings.of(row).field(:regions)
    get integrations_url, headers: inertia_headers
    shown = inertia_props["integrations"].find { |integration| integration["provider"] == "northflank" }["environments"].sole["settings"]
    assert_equal [ { "label" => "Regions", "value" => "US East (N. Virginia), Europe (Ireland)" } ], shown

    post integrations_url, params: { provider: "northflank", name: "Northflank two", credentials: { api_token: "nf", project: "shop" }, fields: { regions: [ "mars-1" ] } }
    assert_equal "Regions can only be US East (N. Virginia) or Europe (Ireland).", session[:inertia_errors].to_h.with_indifferent_access[:connection]
  end

  test "the gallery offers a provider's regions and the fields it asks" do
    get integrations_url, headers: inertia_headers

    datadog = inertia_props["providers"].find { |provider| provider["key"] == "datadog" }
    assert_equal %w[us1 us3 us5 eu1 ap1 ap2 uk1], datadog["regions"].map { |region| region["key"] }
    assert_equal [], datadog["connectFields"]
  end

  private

  def flow = { authorize_url: "https://auth.example/authorize", state: "abc", verifier: "v", client_id: "cid", token_endpoint: "https://auth.example/token" }

  def connect_datadog(region:, environment:)
    Integrations::OauthClient.stubs(:begin_flow).returns(flow)
    Integrations::OauthClient.stubs(:exchange).returns("access_token" => "at")
    get oauth_start_integrations_url(provider: "datadog", region: region, environment_id: environment.id)
    get oauth_callback_integrations_url(state: "abc", code: "c")
    Integrations::OauthClient.unstub(:begin_flow)
    Integrations::OauthClient.unstub(:exchange)
  end

  # A provider with regions and every kind of connect field, as one whose server's address names an organization and a
  # project would list them.
  def with_acme
    entries = IntegrationProvider.all
    acme = IntegrationProvider::Entry.new(
      key: "acme", name: "Acme", category: "Observability", mark: "AC", color: "#000000", description: "Acme.", kind: Integration::KIND_MCP,
      server_url: "https://mcp.acme.example/mcp", source_links: IntegrationProvider::SOURCE_LINKS_NONE, source_links_note: "None.",
      map: IntegrationProvider::MAP_NONE, map_note: "None.",
      regions: [ IntegrationProvider::Region.new(key: "us", label: "US", server_url: "https://mcp.acme.example/mcp"),
                 IntegrationProvider::Region.new(key: "eu", label: "EU", server_url: "https://mcp.eu.acme.example/mcp") ],
      connect_fields: [
        IntegrationProvider::ConnectField.new(key: "organization", label: "Organization", hint: "Its slug.", path: true),
        IntegrationProvider::ConnectField.new(key: "project", label: "Project", hint: "Its slug.", path: true, optional: true),
        IntegrationProvider::ConnectField.new(key: "account", label: "Account", hint: "Its number.", numeric: true)
      ]
    )
    IntegrationProvider.stubs(:all).returns(entries + [ acme ])
    yield
  end
end
