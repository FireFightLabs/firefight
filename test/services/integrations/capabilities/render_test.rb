require "test_helper"

class Integrations::Capabilities::RenderTest < ActiveSupport::TestCase
  TOOLS = Integrations::Capabilities::Render::TOOLS.values.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render", slug: "render")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { api_key: "x" }.to_json)
    Integrations::Packs::Render.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    resource!(ResourceMap::KIND_SERVICE, "srv-web", "web")
    resource!(ResourceMap::KIND_DATABASE, "red-1", "cache")
    resource!(ResourceMap::KIND_SITE, "srv-docs", "docs")
  end

  test "logs, metrics, deploys and status run as Render's own tools by the resource's Render id" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "stream" => "requests", "minutes" => 30)
    assert_equal [ "render.search_logs", { "resource" => "srv-web", "type" => "request", "text" => "timeout", "minutes" => 30 } ],
                 [ logs.tool.action_key, logs.arguments ]

    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "cache", "metrics" => %w[cpu tcp_connections])
    assert_equal({ "resource" => "red-1", "metrics" => %w[cpu active_connections] }, metrics.arguments)
    assert_equal "list_deployments", resolve(Integrations::Capabilities::DEPLOYS, "resource" => "docs").tool.name
    assert_equal({ "resource" => "red-1" }, resolve(Integrations::Capabilities::STATUS, "resource" => "cache").arguments)
  end

  test "what Render cannot answer is refused in words" do
    assert_match "cannot leave lines out", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "exclude" => "healthz")
    assert_match "stream must be app, build, requests", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "cdn")
    assert_match "Render does not keep network_in", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "network_in" ])
    assert_match "no connection offers metrics", unroutable(Integrations::Capabilities::METRICS, "resource" => "docs")
    assert_match "no connection offers scaling", unroutable(Integrations::Capabilities::SCALE, "resource" => "cache", "instances" => 2)
  end

  test "a web service's latency is the 95th percentile Render keeps, and a resource's disk its persistent disk usage" do
    assert_equal %w[latency_p95 disk], resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[latency_p95 disk]).arguments["metrics"]
    latency = Integrations::Packs::Render::METRICS.fetch("latency_p95")
    assert_equal [ "http-latency", { "quantile" => 0.95 } ], [ latency.path, latency.query ]
    assert_equal "disk-usage", Integrations::Packs::Render::METRICS.fetch("disk").path
    assert_equal "active_connections", Integrations::Capabilities.baseline_metric(@row, "tcp_connections", ResourceMap::KIND_DATABASE)
    assert_empty Integrations::Capabilities::Render::METRIC_MAP.keys - Integrations::Capabilities::METRIC_NAMES
    assert_empty Integrations::Capabilities::Render::METRIC_MAP.values - Integrations::Packs::Render::METRICS.keys
  end

  test "a rollback, restart and scale run as Render's change tools, with what the change needs" do
    rollback = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "dep-1")
    assert_equal [ "rollback_deploy", { "resource" => "srv-web", "deploy" => "dep-1" } ], [ rollback.tool.name, rollback.arguments ]
    assert_equal({ "resource" => "red-1" }, resolve(Integrations::Capabilities::RESTART, "resource" => "cache").arguments)
    assert_equal({ "resource" => "srv-web", "instances" => 3 }, resolve(Integrations::Capabilities::SCALE, "resource" => "web", "instances" => "3").arguments)
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web") }
  end

  test "every tool the adapter runs is one the pack declares, and Halon is offered the capabilities instead" do
    assert_empty TOOLS - Integrations::Packs::Render.tool_definitions.map(&:name)
    assert Integrations::Capabilities.wrapped?(@workspace.integrations.find_by!(slug: "render").tools.find_by!(name: "scale_service"))
    assert_not Integrations::Capabilities.wrapped?(@workspace.integrations.find_by!(slug: "render").tools.find_by!(name: "list_events"))
    assert_equal "Halon can read its logs, read its metrics, see what was deployed, check how a resource stands, see how long its runs usually take, " \
                 "roll a resource back, restart a service, and scale a service for anything Render runs, through the tools that are switched on. It also uses " \
                 "Render's other tools that are switched on.", Integrations::Capabilities.halon_sentence("render", "Render")
  end

  test "run history is Render's deploy history of a service or site, and a datastore has none" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "web", "name" => "deploy", "limit" => 5)
    assert_equal [ "deploy_history", { "resource" => "srv-web", "name" => "deploy", "limit" => 5 } ], [ history.tool.name, history.arguments ]
    assert_equal "deploy_history", resolve(Integrations::Capabilities::HISTORY, "resource" => "docs").tool.name
    assert_match "no connection offers run history", unroutable(Integrations::Capabilities::HISTORY, "resource" => "cache")
  end

  private

  def resource!(kind, id, name)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "render", account: "tea-1", kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
