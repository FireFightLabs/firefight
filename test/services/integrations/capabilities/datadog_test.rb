require "test_helper"

class Integrations::Capabilities::DatadogTest < ActiveSupport::TestCase
  RANGE_OBJECT = { "type" => "object", "properties" => { "query" => { "type" => "string" }, "service" => { "type" => "string" },
                                                         "time_range" => { "type" => "object", "properties" => { "from" => {}, "to" => {} } } } }.freeze
  TOP_LEVEL = { "type" => "object", "properties" => { "query" => { "type" => "string" }, "from" => {}, "to" => {}, "limit" => {} } }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[search_logs describe_resource].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    @datadog_row = datadog.integration_environments.create!
    @logs = datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true, params_schema: RANGE_OBJECT)
    datadog.tools.create!(name: "search_datadog_spans", description: "Spans", read_only: true, enabled: true, params_schema: TOP_LEVEL)
    metric_schema = RANGE_OBJECT.deep_dup.tap { |schema| schema["properties"] = schema["properties"].except("service").merge("metric_name" => { "type" => "string" }) }
    datadog.tools.create!(name: "get_datadog_metric", description: "Metric", read_only: true, enabled: true, params_schema: metric_schema)
    northflank.tools.create!(name: "query_metrics", description: "Metrics", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Datadog answers logs for a service Northflank runs by default, and Northflank answers its status" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "minutes" => 30)

    assert_equal [ @datadog_row, "search_datadog_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal "\"timeout\"", logs.arguments["query"]
    assert_equal "web", logs.arguments["service"]
    assert_equal({ "from" => "now-30m", "to" => "now" }, logs.arguments["time_range"])
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
  end

  test "Datadog answers cpu or memory asked alone, and the platform answers every other metric" do
    cpu = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "cpu" ], "minutes" => 30)

    assert_equal [ @datadog_row, "get_datadog_metric" ], [ cpu.environment_row, cpu.tool.name ]
    assert_equal({ "metric_name" => "container.cpu.usage", "query" => "avg:container.cpu.usage{service:web}",
                   "time_range" => { "from" => "now-30m", "to" => "now" } }, cpu.arguments)
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu memory]).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "http_5xx" ]).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web").environment_row
    assert_match "one metric a call", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "disk" ], "connection" => "datadog")
    @workspace.integrations.find_by!(slug: "datadog").tools.find_by!(name: "get_datadog_metric").update!(params_schema: TOP_LEVEL.merge("properties" => { "from" => {}, "to" => {} }))
    assert_match "takes its metric in a way", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "cpu" ])
  end

  test "Datadog asked by default carries the platform's call to make when it has no answer, and a named one does not" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web")

    assert_equal [ @northflank_row, "search_logs" ], [ logs.fallback.environment_row, logs.fallback.tool.name ]
    assert_nil resolve(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "datadog").fallback
    assert_nil resolve(Integrations::Capabilities::STATUS, "resource" => "web").fallback
  end

  test "an answer is definitive unless it is an error, empty, or a list with nothing in it" do
    answer = ->(text, error: false) { Integrations::Capabilities.definitive?({ "content" => [ { "type" => "text", "text" => text } ], "isError" => error }) }

    assert answer.call("12 log lines for web")
    assert answer.call({ "data" => [ { "message" => "timeout" } ], "meta" => {} }.to_json)
    assert_not answer.call({ "data" => [], "meta" => { "page" => 1 } }.to_json)
    assert_not answer.call("[]")
    assert_not answer.call("  ")
    assert_not answer.call("rate limited", error: true)
    assert_not Integrations::Capabilities.definitive?(nil)
    assert_not answer.call({ "series" => [ { "metric" => "container.cpu.usage", "pointlist" => [] } ] }.to_json)
    assert_not Integrations::Capabilities.definitive?({ "content" => [ { "type" => "text", "text" => "[]" },
                                                                      { "type" => "text", "text" => Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: "Datadog", url: "https://app.datadoghq.com/logs")) } ] })
    assert Integrations::Capabilities.definitive?({ "content" => [], "structuredContent" => { "logs" => [ { "message" => "x" } ] } })
  end

  test "Datadog is passed over when its tool is off, the caller may not run it, or it cannot take what was asked" do
    @logs.update!(enabled: false)
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    @logs.update!(enabled: true)

    northflank_only = Integration::Tool.in_workspace(@workspace).reject { |tool| tool.integration.provider == "datadog" }
    assert_equal @northflank_row, Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, { "resource" => "web" }, northflank_only).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build").environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "time.?out").environment_row
  end

  test "a Datadog connection wired to another environment does not answer for this one" do
    @datadog_row.update!(catalog_entry_id: catalog_entries(:development_env).id)

    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_match "no connection offers traces", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")
  end

  test "when Datadog cannot take what was asked and nothing else can answer, it says why" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "render", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "api-id",
                                  name: "api", first_seen_at: Time.current, last_seen_at: Time.current)

    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "api", "stream" => "build")
    assert_equal @datadog_row, resolve(Integrations::Capabilities::LOGS, "resource" => "api").environment_row
  end

  test "naming a connection asks it instead, and all asks every one, each in its own call" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "northflank").environment_row

    calls = Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "all")
    assert_equal %w[northflank.search_logs datadog.search_datadog_logs].sort, calls.map { |call| call.tool.action_key }.sort

    build = Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "all", "stream" => "build")
    refused = build.grep(Integrations::Capabilities::Refused).sole
    assert_equal [ @datadog_row, true ], [ refused.environment_row, refused.reason.include?("stream must be app") ]
    assert_equal "northflank.search_logs", build.grep(Integrations::Capabilities::Call).sole.tool.action_key
    assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "x") }
  end

  test "the connection choice offers all for reading only, and points Halon at the team's instructions" do
    connections = %w[northflank datadog]
    logs = Integrations::Capabilities.schema(Integrations::Capabilities.spec(Integrations::Capabilities::LOGS), connections)
    restart = Integrations::Capabilities.schema(Integrations::Capabilities.spec(Integrations::Capabilities::RESTART), connections)

    assert_equal [ *connections, "all" ], logs.dig("properties", "connection", "enum")
    assert_match "team's instructions", logs.dig("properties", "connection", "description")
    assert_equal connections, restart.dig("properties", "connection", "enum")
  end

  test "the arguments follow the parameters the connected server reports, and a service without one goes in the query" do
    spans = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "limit" => 20, "exclude" => "health")

    assert_equal "service:web -\"health\"", spans.arguments["query"]
    assert_equal 20, spans.arguments["limit"]
    assert_equal %w[now-60m now], spans.arguments.values_at("from", "to")
    asked = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")
    assert_equal %w[2026-09-01T10:00:00Z 2026-09-01T11:00:00Z], asked.arguments.values_at("from", "to")
    assert_not spans.arguments.key?("service")
  end

  test "what Datadog cannot do is said, never guessed" do
    assert_match "regular expression", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "x", "connection" => "datadog")
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build", "connection" => "datadog")
    @logs.update!(params_schema: { "type" => "object", "properties" => { "query" => {} } })
    assert_match "time range in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "datadog")
    @logs.update!(params_schema: { "type" => "object", "properties" => { "query" => {}, "from" => { "type" => "integer" }, "to" => { "type" => "integer" } } })
    assert_match "time range in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "datadog")
  end

  test "an adapter routes with what its connection was set up with, and one that does not reach a capability is passed over for the platform" do
    Integrations::Capabilities::Datadog.expects(:route).with { |_key, _resource, _given, tool:, settings:| tool.name == "search_datadog_logs" && settings.region.key == "us1" }
                                       .returns(Integrations::Capabilities::Route.new(tool_name: "search_datadog_logs", arguments: {}))
    assert_equal @datadog_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row

    Integrations::Capabilities::Datadog.unstub(:route)
    Integrations::Capabilities::Datadog.stubs(:reaches?).returns(false)
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
  end

  test "Datadog answers errors for a site too, since a frontend's errors come from the site that serves it" do
    datadog = Integrations::Capabilities::Datadog

    assert datadog.observes?(Integrations::Capabilities::ERRORS, ResourceMap::KIND_SITE)
    assert_not datadog.observes?(Integrations::Capabilities::LOGS, ResourceMap::KIND_SITE)
    assert_equal [ *Integrations::Capabilities::Adapter::APP_KINDS, ResourceMap::KIND_SITE ], Integrations::Capabilities::Adapter::ERROR_KINDS
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
