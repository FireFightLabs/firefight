require "test_helper"

class Integrations::Capabilities::GrafanaTest < ActiveSupport::TestCase
  # The parameters grafana/mcp-grafana declares for each tool (tools/loki.go, tools/prometheus.go, tools/tempo.go).
  SCHEMAS = {
    "query_loki_logs" => %w[datasourceUid logql startRfc3339 endRfc3339 limit direction queryType stepSeconds format],
    "query_prometheus" => %w[datasourceUid expr startTime endTime stepSeconds queryType projectName],
    "search_tempo_traces" => %w[datasourceUid query start end]
  }.freeze
  DATASOURCES = [
    { "uid" => "loki-uid", "name" => "Loki", "type" => "loki", "default" => false },
    { "uid" => "prom-uid", "name" => "Prometheus", "type" => "prometheus", "default" => true },
    { "uid" => "tempo-uid", "name" => "Tempo", "type" => "tempo", "default" => false }
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[search_logs describe_resource query_metrics].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    grafana = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana", slug: "grafana",
                                              settings: { "server_url" => "https://mcp-grafana.acme.dev/mcp" })
    @grafana_row = grafana.integration_environments.create!(base_config: { "learned" => { "datasources" => DATASOURCES, "address" => "https://acme.grafana.net" } })
    @tools = SCHEMAS.to_h do |name, properties|
      [ name, grafana.tools.create!(name: name, description: name, read_only: true, enabled: true,
                                    params_schema: { "type" => "object", "properties" => properties.index_with { {} } }) ]
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Grafana answers logs from Loki for a service Northflank runs by default, and Northflank answers its status" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "exclude" => "health", "regex" => "5\\d\\d", "minutes" => 30, "limit" => 50)

    assert_equal [ @grafana_row, "query_loki_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal({ "datasourceUid" => "loki-uid", "logql" => "{service_name=\"web\"} |= \"timeout\" != \"health\" |~ \"5\\\\d\\\\d\"",
                   "startRfc3339" => "now-30m", "endRfc3339" => "now", "limit" => 50, "direction" => "backward" }, logs.arguments)
    assert_equal 100, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "limit" => 5000).arguments["limit"]
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build").environment_row
  end

  test "a quote or a backslash in what was asked stays a literal in LogQL and TraceQL" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "say \"hi\" \\ bye")
    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "text" => "GET /a.b?(x)")

    assert_equal "{service_name=\"web\"} |= \"say \\\"hi\\\" \\\\ bye\"", logs.arguments["logql"]
    assert_equal "{ resource.service.name = \"web\" && name =~ \".*GET /a\\\\.b\\\\?\\\\(x\\\\).*\" }", traces.arguments["query"]
  end

  test "Grafana answers cpu and memory in one Prometheus query, and the platform answers every other metric" do
    asked = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu memory], "minutes" => 60)

    assert_equal [ @grafana_row, "query_prometheus" ], [ asked.environment_row, asked.tool.name ]
    assert_equal "label_replace(sum by (pod) (rate(container_cpu_usage_seconds_total{container=\"web\"}[300s])), \"firefight_metric\", \"cpu\", \"\", \"\") or " \
                 "label_replace(sum by (pod) (container_memory_working_set_bytes{container=\"web\"}) / 1048576, \"firefight_metric\", \"memory\", \"\", \"\")",
                 asked.arguments["expr"]
    assert_equal({ "datasourceUid" => "prom-uid", "startTime" => "now-60m", "endTime" => "now", "stepSeconds" => 60, "queryType" => "range" },
                 asked.arguments.except("expr"))
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu http_5xx]).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web").environment_row
    assert_match "only cpu and memory", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "disk" ], "connection" => "grafana")
  end

  test "Grafana answers traces from Tempo, the only connection that keeps them" do
    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")

    assert_equal({ "datasourceUid" => "tempo-uid", "query" => "{ resource.service.name = \"web\" }", "start" => "2026-09-01T10:00:00Z",
                   "end" => "2026-09-01T11:00:00Z" }, traces.arguments)
    assert_nil traces.fallback
  end

  test "asked by default it carries the platform's call to make when it has no answer, and a named one does not" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web")

    assert_equal [ @northflank_row, "search_logs" ], [ logs.fallback.environment_row, logs.fallback.tool.name ]
    assert_nil resolve(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "grafana").fallback
  end

  test "a connection whose datasource is not known, or one of several with none the default, is passed over for the platform" do
    @grafana_row.update!(base_config: {})
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_match "no connection offers traces", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")

    two = DATASOURCES + [ { "uid" => "loki-eu", "name" => "Loki EU", "type" => "loki", "default" => false } ]
    @grafana_row.update!(base_config: { "learned" => { "datasources" => two } })
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    two.last["default"] = true
    @grafana_row.update!(base_config: { "learned" => { "datasources" => two } })
    assert_equal "loki-eu", resolve(Integrations::Capabilities::LOGS, "resource" => "web").arguments["datasourceUid"]
  end

  test "a tool the connected server describes without an argument Firefight writes is refused in words" do
    @tools.fetch("query_loki_logs").update!(params_schema: { "type" => "object", "properties" => { "datasourceUid" => {}, "logql" => {} } })

    assert_match "takes its arguments in a way Firefight does not know (no startRfc3339, endRfc3339, limit, direction)",
                 unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "grafana")
  end

  test "Loki's lines read back newest first with the link to Grafana kept, and an empty answer stays Grafana's own" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web")
    link = { "type" => "text", "text" => Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: "Grafana", url: "https://acme.grafana.net/explore")) }
    body = { "data" => [
      { "timestamp" => "1788000000000000000", "line" => "older", "labels" => { "pod" => "web-1" } },
      { "timestamp" => "1788000060000000000", "line" => "newer", "labels" => { "service_name" => "web" } }
    ], "metadata" => { "linesReturned" => 2 } }

    presented = logs.present_result({ "content" => [ { "type" => "text", "text" => body.to_json }, link ] })
    text = presented["content"].first["text"]

    assert_match(/2 log lines for web in Loki, newest first\.\n2026-08-29T10:41:00Z web newer\n2026-08-29T10:40:00Z web-1 older/, text)
    assert_equal link, presented["content"].last
    empty = { "content" => [ { "type" => "text", "text" => { "data" => [], "hints" => { "summary" => "No data" } }.to_json } ] }
    assert_equal empty, logs.present_result(empty)
    assert_not Integrations::Capabilities.definitive?(logs.present_result(empty))
  end

  test "Prometheus's series read back as a chart per metric with a series per pod" do
    asked = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu memory])
    body = { "data" => [
      { "metric" => { "pod" => "web-1", "firefight_metric" => "cpu" }, "values" => [ [ 1_788_000_000, "0.25" ], [ 1_788_000_060, "0.5" ] ] },
      { "metric" => { "pod" => "web-1", "firefight_metric" => "memory" }, "values" => [ [ 1_788_000_000, "128" ] ] }
    ] }

    presented = asked.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })
    charts = presented.dig("structuredContent", "charts")

    assert_equal [ "CPU of web", "Memory working set of web" ], charts.map { |chart| chart["title"] }
    assert_equal [ "cores", "MiB" ], charts.map { |chart| chart["unit"] }
    assert_equal [ [ "2026-08-29T10:40:00Z", 0.25 ], [ "2026-08-29T10:41:00Z", 0.5 ] ], charts.first["series"].sole["points"]
    assert_match "web-1: min 0.25", presented["content"].first["text"]
  end

  test "Tempo's traces read back slowest first" do
    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web")
    body = { "traces" => [
      { "traceID" => "fast", "rootServiceName" => "web", "rootTraceName" => "GET /", "startTimeUnixNano" => "1788000000000000000", "durationMs" => 12 },
      { "traceID" => "slow", "rootServiceName" => "web", "rootTraceName" => "POST /pay", "startTimeUnixNano" => "1788000060000000000", "durationMs" => 2400,
        "spanSets" => [ { "matched" => 3 } ] }
    ], "metrics" => { "totalBlocks" => 13 } }

    text = traces.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })["content"].first["text"]

    assert_match "2 traces through web in Tempo, slowest first.", text
    assert_match "2026-08-29T10:41:00Z, trace slow, web, POST /pay, 2400 ms, 3 matching spans\n2026-08-29T10:40:00Z, trace fast, web, GET /, 12 ms", text
    assert_not Integrations::Capabilities.definitive?(traces.present_result({ "content" => [ { "type" => "text", "text" => { "traces" => [] }.to_json } ] }))
  end

  test "Halon is told what Grafana answers" do
    assert_equal "Halon can read its logs, read its metrics, and read its traces for the services on the map that Grafana watches, by their name in Grafana, " \
                 "through the tools you switch on. It also uses Grafana's other tools that you switch on.",
                 Integrations::Capabilities.halon_sentence("grafana", "Grafana")
  end

  # Grafana's server is run by each team, so its skills are held to the tools the server documents, in the reference
  # table copied with its guides, and to the capabilities Grafana answers. So are the tools Firefight itself calls.
  test "every tool a Grafana skill or Firefight's own Grafana reads name is one Grafana's server documents" do
    documented = Chat::Skill.reference("grafana", "reference/mcp-tools-table.md").scan(/^\| `([a-z0-9_]+)`/).flatten
    adapter = Integrations::Capabilities::Grafana
    capabilities = adapter.capabilities.map { |key| Integrations::Capabilities.spec(key).tool_name }

    called = adapter::TOOLS.values + [ Integrations::HealthProbes::Grafana::LIST_DATASOURCES, Integrations::HealthProbes::Grafana::GENERATE_DEEPLINK ]
    called.each { |tool| assert_includes documented, tool }
    skills = Chat::Skill.all.select { |skill| skill.source == adapter::PROVIDER_KEY }
    assert_equal %w[grafana_logs grafana_metrics grafana_traces grafana_triage], skills.map(&:name).sort
    skills.each do |skill|
      skill.tools.each { |tool| assert_includes documented + capabilities, tool, "#{skill.name} names #{tool}" }
      skill.steps.scan(/`([^`]+)`/).flatten.each { |name| assert_includes skill.tools, name, "#{skill.name} calls #{name} without listing it" }
    end
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
