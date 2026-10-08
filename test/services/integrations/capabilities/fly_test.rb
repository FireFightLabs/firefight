require "test_helper"

class Integrations::Capabilities::FlyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @fly = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly.io", slug: "fly")
    @row = @fly.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    Integrations::Packs::Fly.tool_definitions.each do |definition|
      @fly.tools.create!(name: definition.name, description: definition.name, read_only: definition.read_only, enabled: true, params_schema: definition.params_schema)
    end
    resource!(ResourceMap::KIND_SERVICE, "web")
    resource!(ResourceMap::KIND_DATABASE, "pg1", name: "main-db")
  end

  test "an app's logs, metrics, releases and status are its own tools' calls, by its name" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "exclude" => "health", "minutes" => 30)
    assert_equal [ "fly.search_logs", { "resource" => "web", "text" => "timeout", "exclude" => "health", "minutes" => 30 } ], [ logs.tool.action_key, logs.arguments ]

    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu http_5xx])
    assert_equal({ "resource" => "web", "metrics" => %w[cpu http_5xx] }, metrics.arguments)
    assert_equal "list_deployments", resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web").tool.name
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS, "resource" => "main-db").tool.name
  end

  test "latency is the 95th percentile of Fly's edge response times, read for the baselines too" do
    assert_equal %w[latency_p95], resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[latency_p95]).arguments["metrics"]
    latency = Integrations::Packs::Fly::METRICS.fetch("latency_p95")
    assert_equal "histogram_quantile(0.95, sum by (le) (rate(fly_edge_http_response_time_seconds_bucket{app=\"web\"}[60s]))) * 1000",
                 format(latency.total, app: "web", window: "60s")
    assert_equal [ "ms", nil ], [ latency.unit, latency.per_instance ]
    assert_includes Integrations::Packs::Fly::BASELINE_METRICS, "latency_p95"
    assert_equal "latency_p95", Integrations::Capabilities.baseline_metric(@row, "latency_p95", ResourceMap::KIND_SERVICE)
  end

  test "a rollback and a restart go to the change tools, and what Fly does not keep or offer is refused in words" do
    assert_equal [ "rollback_release", { "resource" => "web", "release" => "41" } ],
                 resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "41").then { |call| [ call.tool.name, call.arguments ] }
    assert_equal "restart_app", resolve(Integrations::Capabilities::RESTART, "resource" => "web").tool.name

    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build")
    assert_match "Fly.io does not keep disk", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "disk" ])
    assert_match "no connection offers scaling", unroutable(Integrations::Capabilities::SCALE, "resource" => "web", "instances" => 2)
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "main-db")
  end

  test "every tool the adapter runs is one the pack declares, every metric is in the shared vocabulary, and the wrapped ones are not offered twice" do
    declared = Integrations::Packs::Fly.tool_definitions.map(&:name)

    assert_empty Integrations::Capabilities::Fly::TOOLS.values - declared
    assert_empty Integrations::Packs::Fly::METRICS.keys - Integrations::Capabilities::METRIC_NAMES
    assert Integrations::Capabilities.wrapped?(@fly.tools.find_by!(name: "rollback_release"))
    assert_equal %w[logs metrics deploys status history rollback restart], Integrations::Capabilities::Fly.capabilities
  end

  test "run history is an app's releases, by its name, and a Postgres cluster has none" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "web", "name" => "deploy")
    assert_equal [ "deploy_history", { "resource" => "web", "name" => "deploy" } ], [ history.tool.name, history.arguments ]
    assert_match "no connection offers run history", unroutable(Integrations::Capabilities::HISTORY, "resource" => "main-db")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message

  def resource!(kind, id, name: id)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "fly", account: "acme", kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
