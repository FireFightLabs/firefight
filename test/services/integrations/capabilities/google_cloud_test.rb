require "test_helper"

class Integrations::Capabilities::GoogleCloudTest < ActiveSupport::TestCase
  RUN_ID = "projects/acme-prod/locations/us-central1/services/web".freeze
  SQL_ID = "acme-prod:us-central1:orders".freeze
  VM_ID = "projects/acme-prod/zones/us-central1-a/instances/worker-1".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud", slug: "gcp")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @row.store_fields!("project" => "acme-prod")
    Integrations::Packs::GoogleCloud.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    resource!(ResourceMap::KIND_SERVICE, RUN_ID, "web", Integrations::Packs::GoogleCloud::TYPE_RUN)
    resource!(ResourceMap::KIND_DATABASE, SQL_ID, "orders", Integrations::Packs::GoogleCloud::TYPE_SQL)
    resource!(ResourceMap::KIND_VIRTUAL_MACHINE, VM_ID, "worker-1", Integrations::Packs::GoogleCloud::TYPE_MACHINE)
  end

  test "every capability runs as the pack's own tool, by the resource's id, with the request's own words" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "stream" => "requests", "minutes" => 30)
    assert_equal [ "gcp.search_logs", { "resource" => RUN_ID, "text" => "timeout", "stream" => "requests", "minutes" => 30 } ], [ logs.tool.action_key, logs.arguments ]

    assert_equal({ "resource" => RUN_ID, "limit" => 5 }, resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web", "limit" => 5).arguments)
    assert_equal "list_revisions", resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web").tool.name
    assert_equal({ "resource" => RUN_ID, "text" => "Timeout" }, resolve(Integrations::Capabilities::ERRORS, "resource" => "web", "text" => "Timeout").arguments)
    assert_equal({ "resource" => RUN_ID, "revision" => "web-00001-abc" }, resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "web-00001-abc").arguments)
    assert_equal({ "resource" => RUN_ID, "min_instances" => 3 }, resolve(Integrations::Capabilities::SCALE, "resource" => "web", "instances" => 3).arguments)
    assert_equal [ "restart_resource", { "resource" => SQL_ID } ], resolve(Integrations::Capabilities::RESTART, "resource" => "orders").then { |call| [ call.tool.name, call.arguments ] }
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS, "resource" => "worker-1").tool.name
  end

  test "metrics pass only the names Google keeps for that kind of resource" do
    assert_equal({ "resource" => VM_ID, "metrics" => %w[cpu network_in], "minutes" => 15 },
                 resolve(Integrations::Capabilities::METRICS, "resource" => "worker-1", "metrics" => %w[cpu network_in], "minutes" => 15).arguments)
    assert_equal({ "resource" => SQL_ID, "metrics" => [ "tcp_connections" ] }, resolve(Integrations::Capabilities::METRICS, "resource" => "orders", "metrics" => [ "tcp_connections" ]).arguments)
    assert_match "Google Cloud does not keep disk for this resource", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "disk" ])
  end

  test "a Cloud Run service's latency is the 95th percentile of its request latencies, kept as a baseline too" do
    assert_equal [ "latency_p95" ], resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "latency_p95" ]).arguments["metrics"]
    latency = Integrations::Packs::GoogleCloud::Metrics::RUN.fetch("latency_p95")
    assert_equal [ "run.googleapis.com/request_latencies", "ALIGN_PERCENTILE_95", "ms" ], [ latency.type, latency.aligner, latency.unit ]
    assert_includes Integrations::Packs::GoogleCloud::Metrics::BASELINES.fetch(Integrations::Packs::GoogleCloud::TYPE_RUN), "latency_p95"
    assert_match "does not keep latency_p95", unroutable(Integrations::Capabilities::METRICS, "resource" => "orders", "metrics" => [ "latency_p95" ])
    assert_equal "latency_p95", Integrations::Capabilities.baseline_metric(@row, "latency_p95", ResourceMap::KIND_SERVICE)
  end

  test "what Google Cloud does not offer for a kind finds no connection, and every tool is wrapped, and the details say what a restart reaches" do
    assert_match "no connection offers a restart for it", unroutable(Integrations::Capabilities::RESTART, "resource" => "web")
    assert_match "no connection offers deploys for it", unroutable(Integrations::Capabilities::DEPLOYS, "resource" => "orders")
    assert_equal %w[search_logs query_metrics list_revisions describe_resource error_groups rollback_service restart_resource scale_service],
                 Integrations::Capabilities::GoogleCloud::WRAPPED
    assert_match "restart a Cloud SQL database or a virtual machine", Integrations::Capabilities.halon_sentence("google_cloud", "Google Cloud")
    assert_equal Integrations::Capabilities::SPECS.keys - [ Integrations::Capabilities::TRACES ], Integrations::Capabilities::GoogleCloud.capabilities
  end

  test "a change waits for its write tool to be switched on, and says so" do
    @row.integration.tools.find_by!(name: "rollback_service").update!(enabled: false)

    assert_match "would answer this with its rollback_service tool, which is switched off", unroutable(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "x")
  end

  private

  def resource!(kind, id, name, type)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "google_cloud", account: "acme-prod", kind: kind, external_id: id, name: name,
                                  details: { "type" => type }, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "a Cloud Run service's run history is its revisions, and nothing else has one" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "web", "name" => "revision", "limit" => 3)
    assert_equal [ "list_revisions", { "resource" => RUN_ID, "limit" => 3 } ], [ history.tool.name, history.arguments ]
    assert_match "no connection offers run history", unroutable(Integrations::Capabilities::HISTORY, "resource" => "orders")
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
