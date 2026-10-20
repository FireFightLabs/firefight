require "test_helper"

class Integrations::Capabilities::AzureTest < ActiveSupport::TestCase
  GROUP = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/shop/providers".freeze
  WEB_ID = "#{GROUP}/Microsoft.Web/sites/storefront".freeze
  APP_ID = "#{GROUP}/Microsoft.App/containerApps/api".freeze
  SQL_ID = "#{GROUP}/Microsoft.Sql/servers/shop-sql/databases/orders".freeze
  PG_ID = "#{GROUP}/Microsoft.DBforPostgreSQL/flexibleServers/catalog".freeze
  REGISTRY_ID = "#{GROUP}/Microsoft.ContainerRegistry/registries/acme".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure", slug: "azure")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    Integrations::Packs::Azure.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    resource!(ResourceMap::KIND_SERVICE, WEB_ID, "storefront", Integrations::Packs::Azure::TYPE_WEB)
    resource!(ResourceMap::KIND_SERVICE, APP_ID, "api", Integrations::Packs::Azure::TYPE_CONTAINER)
    resource!(ResourceMap::KIND_DATABASE, SQL_ID, "orders", Integrations::Packs::Azure::TYPE_SQL)
    resource!(ResourceMap::KIND_DATABASE, PG_ID, "catalog", Integrations::Packs::Azure::TYPE_POSTGRES)
    resource!(ResourceMap::KIND_BUILD_SERVICE, REGISTRY_ID, "acme", Integrations::Packs::Azure::TYPE_REGISTRY)
  end

  test "a container registry's run history is its ACR Tasks runs, its logs a run's log, and it holds nothing else" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "acme", "run" => "ca2")
    assert_equal [ "list_registry_runs", { "resource" => REGISTRY_ID, "run" => "ca2", "limit" => 20 } ], [ history.tool.name, history.arguments ]
    log = resolve(Integrations::Capabilities::LOGS, "resource" => "acme", "stream" => "build", "deployment" => "ca2", "text" => "ERR")
    assert_equal [ "registry_run_log", { "resource" => REGISTRY_ID, "run" => "ca2", "text" => "ERR" } ], [ log.tool.name, log.arguments ]
    assert_equal({ "resource" => REGISTRY_ID }, resolve(Integrations::Capabilities::LOGS, "resource" => "acme").arguments)
    assert_match "stream must be build", unroutable(Integrations::Capabilities::LOGS, "resource" => "acme", "stream" => "app")
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS, "resource" => "acme").tool.name
    assert_match "no connection offers a restart", unroutable(Integrations::Capabilities::RESTART, "resource" => "acme")
  end

  test "every capability runs as the pack's own tool, by the resource's id" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "storefront", "stream" => "requests", "text" => "500")
    assert_equal [ "azure.search_logs", { "resource" => WEB_ID, "stream" => "requests", "text" => "500" } ], [ logs.tool.action_key, logs.arguments ]
    assert_equal "list_deployments", resolve(Integrations::Capabilities::DEPLOYS, "resource" => "api").tool.name
    assert_equal({ "resource" => WEB_ID, "to" => "staging" }, resolve(Integrations::Capabilities::ROLLBACK, "resource" => "storefront", "to" => "staging").arguments)
    assert_equal({ "resource" => APP_ID, "instances" => 2 }, resolve(Integrations::Capabilities::SCALE, "resource" => "api", "instances" => 2).arguments)
    assert_equal [ "restart_resource", { "resource" => PG_ID } ], resolve(Integrations::Capabilities::RESTART, "resource" => "catalog").then { |call| [ call.tool.name, call.arguments ] }
  end

  test "metrics pass only the names Azure Monitor keeps for that kind of resource, told apart by its type on the map" do
    assert_equal({ "resource" => PG_ID, "metrics" => [ "tcp_connections" ] }, resolve(Integrations::Capabilities::METRICS, "resource" => "catalog", "metrics" => [ "tcp_connections" ]).arguments)
    assert_match "Azure does not keep tcp_connections for this resource", unroutable(Integrations::Capabilities::METRICS, "resource" => "orders", "metrics" => [ "tcp_connections" ])
    assert_match "Azure does not keep cpu_time", unroutable(Integrations::Capabilities::METRICS, "resource" => "api", "metrics" => [ "cpu_time" ])
    assert_equal({ "resource" => WEB_ID, "metrics" => [ "cpu_time" ] }, resolve(Integrations::Capabilities::METRICS, "resource" => "storefront", "metrics" => [ "cpu_time" ]).arguments)
  end

  test "Azure answers no errors or traces, and a database has no deploys" do
    assert_equal Integrations::Capabilities::SPECS.keys - [ Integrations::Capabilities::ERRORS, Integrations::Capabilities::TRACES ], Integrations::Capabilities::Azure.capabilities
    assert_match "no connection offers deploys for it", unroutable(Integrations::Capabilities::DEPLOYS, "resource" => "catalog")
    assert_equal %w[search_logs deployment_log registry_run_log query_metrics list_deployments list_registry_runs describe_resource rollback_app restart_resource scale_app],
                 Integrations::Capabilities::Azure::WRAPPED
    assert_match "restart an app or a PostgreSQL server", Integrations::Capabilities.halon_sentence("azure", "Azure")
  end

  test "an app's run history is its deployments, and a Container App, which keeps no end to a revision, has none" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "storefront")
    assert_equal [ "list_deployments", { "resource" => WEB_ID, "limit" => Integrations::Capabilities::History::LIMIT } ], [ history.tool.name, history.arguments ]
    assert_match "not when it finished rolling out", unroutable(Integrations::Capabilities::HISTORY, "resource" => "api")
    assert_match "no connection offers run history", unroutable(Integrations::Capabilities::HISTORY, "resource" => "catalog")
  end

  test "a run is read by its deployment id, and an app's build log is the deployment's log, the one named or the newest" do
    assert_equal({ "resource" => WEB_ID, "deployment" => "abc123", "limit" => 20 }, resolve(Integrations::Capabilities::HISTORY, "resource" => "storefront", "run" => "abc123").arguments)
    build = resolve(Integrations::Capabilities::LOGS, "resource" => "storefront", "stream" => "build", "deployment" => "abc123", "text" => "x")
    assert_equal [ "deployment_log", { "resource" => WEB_ID, "deployment" => "abc123" } ], [ build.tool.name, build.arguments ]
    assert_equal({ "resource" => WEB_ID }, resolve(Integrations::Capabilities::LOGS, "resource" => "storefront", "stream" => "build").arguments)
    assert_match "Azure keeps build logs for an App Service or Function app's deployments", unroutable(Integrations::Capabilities::LOGS, "resource" => "api", "stream" => "build")
  end

  private

  def resource!(kind, id, name, type)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "azure", account: "11111111-2222-3333-4444-555555555555", kind: kind, external_id: id,
                                  name: name, details: { "type" => type }, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
