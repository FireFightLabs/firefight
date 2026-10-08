require "test_helper"

class Integrations::Capabilities::TinybirdTest < ActiveSupport::TestCase
  PACK = Integrations::Packs::Tinybird

  setup do
    @workspace = workspaces(:slack_workspace_one)
    tinybird = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: PACK::PROVIDER_KEY, name: "Tinybird", slug: "tinybird")
    @row = tinybird.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "p.x" }.to_json)
    PACK.tool_definitions.each do |definition|
      tinybird.tools.create!(name: definition.name, description: definition.description, read_only: true, enabled: true, params_schema: definition.params_schema)
    end
    resource("analytics", "w-1", ResourceMap::KIND_DATABASE, PACK::TYPE_WORKSPACE)
    resource("events", "t_events", ResourceMap::KIND_DATABASE, PACK::TYPE_DATASOURCE)
    resource("top_pages", "t_top", ResourceMap::KIND_FUNCTION, PACK::TYPE_ENDPOINT)
  end

  test "an endpoint's logs are its requests, a data source's its operations, and the workspace's either by stream" do
    assert_equal [ "endpoint_requests", { "endpoint" => "t_top", "text" => "timeout", "minutes" => 30 } ],
                 route(Integrations::Capabilities::LOGS, "resource" => "top_pages", "text" => "timeout", "minutes" => 30, "stream" => "requests")
    assert_equal [ "datasource_operations", { "datasource" => "t_events", "regex" => "JSON.*" } ],
                 route(Integrations::Capabilities::LOGS, "resource" => "events", "regex" => "JSON.*")
    assert_equal [ "endpoint_requests", { "limit" => 5 } ], route(Integrations::Capabilities::LOGS, "resource" => "analytics", "stream" => "requests", "limit" => 5)
    assert_equal [ "datasource_operations", {} ], route(Integrations::Capabilities::LOGS, "resource" => "analytics")
  end

  test "status and errors name the resource by its id, and the workspace by nothing" do
    assert_equal [ "describe_resource", { "name" => "t_events" } ], route(Integrations::Capabilities::STATUS, "resource" => "events")
    assert_equal [ "describe_resource", {} ], route(Integrations::Capabilities::STATUS, "resource" => "analytics")
    assert_equal [ "list_errors", { "name" => "t_top", "text" => "Memory", "limit" => 3 } ],
                 route(Integrations::Capabilities::ERRORS, "resource" => "top_pages", "text" => "Memory", "limit" => 3)
  end

  test "run history is the workspace's jobs, an endpoint's are its pipe's, and a data source has none of its own" do
    assert_equal [ "jobs", { "job_type" => "deployment", "days" => PACK::MAX_JOB_DAYS, "limit" => 20 } ],
                 route(Integrations::Capabilities::HISTORY, "resource" => "analytics", "name" => "deployment")
    assert_equal [ "jobs", { "days" => PACK::MAX_JOB_DAYS, "limit" => 20 } ], route(Integrations::Capabilities::HISTORY, "resource" => "top_pages")
    assert_match "names the pipe each job ran", unroutable(Integrations::Capabilities::HISTORY, "resource" => "events")
  end

  test "metrics are an endpoint's or the workspace's requests, and deploys are the workspace's deployment jobs" do
    assert_equal [ "endpoint_metrics", { "endpoint" => "t_top", "metrics" => %w[requests http_5xx], "minutes" => 120 } ],
                 route(Integrations::Capabilities::METRICS, "resource" => "top_pages", "metrics" => %w[requests http_5xx], "minutes" => 120)
    assert_equal [ "endpoint_metrics", {} ], route(Integrations::Capabilities::METRICS, "resource" => "analytics")
    assert_equal [ "jobs", { "job_type" => "deployment", "limit" => 4 } ], route(Integrations::Capabilities::DEPLOYS, "resource" => "top_pages", "limit" => 4)
  end

  test "an endpoint's latency_p95 is the 95th percentile alone of the latency Tinybird records" do
    assert_equal [ "endpoint_metrics", { "endpoint" => "t_top", "metrics" => [ "latency_p95" ] } ],
                 route(Integrations::Capabilities::METRICS, "resource" => "top_pages", "metrics" => [ "latency_p95" ])
    assert_equal({ "latency_p95" => nil }, PACK::METRICS_READ.fetch("latency_p95").columns)
    assert_empty PACK::METRICS - PACK::METRICS_READ.keys
  end

  test "what Tinybird does not keep is refused in words, and nothing can be changed" do
    assert_match "not for a data source", unroutable(Integrations::Capabilities::METRICS, "resource" => "events")
    assert_match "does not keep memory", unroutable(Integrations::Capabilities::METRICS, "resource" => "top_pages", "metrics" => %w[memory])
    assert_match "nothing else", unroutable(Integrations::Capabilities::LOGS, "resource" => "top_pages", "stream" => "build")
    assert_match "answers no requests", unroutable(Integrations::Capabilities::LOGS, "resource" => "events", "stream" => "requests")
    [ Integrations::Capabilities::ROLLBACK, Integrations::Capabilities::RESTART, Integrations::Capabilities::SCALE ].each do |key|
      assert_match "no connection offers", unroutable(key, "resource" => "top_pages", "to" => "x", "instances" => 1)
    end
  end

  test "status and errors are offered once, the tools that read further stay offered, and the details say what it can do" do
    adapter = Integrations::Capabilities::Tinybird
    assert_equal %w[describe_resource list_errors], PACK.tool_definitions.map(&:name).select { |name| adapter.wraps?(name) }
    assert_equal "Halon can read its logs, read its metrics, see the workspace's deployments, check how a resource stands, " \
                 "see how long its jobs usually take, and read its errors " \
                 "for anything Tinybird runs, through the tools that are switched on. It also uses Tinybird's other tools that are switched on.",
                 Integrations::Capabilities.halon_sentence(PACK::PROVIDER_KEY, "Tinybird")
  end

  private

  def resource(name, id, kind, type)
    ResourceMap::Resource.create!(workspace: @workspace, provider: PACK::PROVIDER_KEY, account: "w-1", kind: kind, external_id: id, name: name,
                                  details: { "type" => type }, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def route(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader).then { |call| [ call.tool.name, call.arguments ] }

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader) }.message
end
