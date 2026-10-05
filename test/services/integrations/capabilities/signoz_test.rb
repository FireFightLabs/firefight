require "test_helper"

class Integrations::Capabilities::SignozTest < ActiveSupport::TestCase
  include ObserverTestHelper

  # The parameters SigNoz's server declares (SigNoz/signoz-mcp-server, internal/handler/tools/logs.go and traces.go).
  LOGS = %w[filter service severity searchText searchScope timeRange start end limit offset].freeze
  TRACES = %w[filter service operation error minDuration maxDuration timeRange start end limit offset selectFields].freeze
  AGGREGATE = %w[aggregation aggregateOn groupBy filter service operation error minDuration maxDuration orderBy limit timeRange start end requestType stepInterval].freeze

  setup do
    run_web_on_northflank
    @row = watch_with("signoz", "SigNoz", { "signoz_search_logs" => LOGS, "signoz_search_traces" => TRACES, "signoz_aggregate_traces" => AGGREGATE })
  end

  test "SigNoz answers logs for a service Northflank runs, by its service name and relative time, and Northflank its status" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "exclude" => "50%_off", "minutes" => 30)

    assert_equal [ @row, "signoz_search_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal({ "service" => "web", "limit" => 200, "timeRange" => "30m", "searchText" => "timeout", "filter" => "body NOT CONTAINS '50\\\\%\\\\_off'" }, logs.arguments)
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
    assert_equal [ @northflank_row, "search_logs" ], [ logs.fallback.environment_row, logs.fallback.tool.name ]
  end

  test "a start and end go as Unix milliseconds, and quotes are escaped as SigNoz's filter syntax asks" do
    asked = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "text" => "it's", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")

    assert_equal [ 1_788_256_800_000, 1_788_260_400_000 ], asked.arguments.values_at("start", "end")
    assert_equal "name CONTAINS 'it\\'s'", asked.arguments["filter"]
    assert_not asked.arguments.key?("timeRange")
  end

  test "log rows read into log lines, and failed spans come first with their page" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web")
    rows = { "status" => "success", "data" => { "type" => "raw", "data" => { "results" => [ { "queryName" => "A", "rows" => [
      { "timestamp" => "2026-10-04T10:00:00Z", "data" => { "body" => "boot", "severity_text" => "INFO" } },
      { "timestamp" => "2026-10-04T10:01:00Z", "data" => { "body" => "timeout calling db", "severity_text" => "ERROR" } }
    ] } ] } } }
    text = logs.present_result(answer(rows))["content"].first["text"]
    assert_match "2 log lines for web in SigNoz, newest first", text
    assert text.index("timeout calling db") < text.index("boot")

    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web")
    spans = { "data" => { "data" => { "results" => [ { "rows" => [
      { "timestamp" => "2026-10-04T10:00:00Z", "data" => { "trace_id" => "a1", "name" => "GET /", "duration_nano" => 9_000_000_000, "has_error" => false } },
      { "timestamp" => "2026-10-04T10:00:00Z", "data" => { "trace_id" => "b2", "name" => "POST /pay", "duration_nano" => 40_000_000, "has_error" => true,
                                                            "status_message" => "card declined" }, "webUrl" => "https://acme.signoz.cloud/trace/b2" }
    ] } ] } } }
    shown = traces.present_result(answer(spans))["content"].first["text"].lines.drop(1)
    assert_equal "trace b2, POST /pay, 40.0 ms, failed: card declined, https://acme.signoz.cloud/trace/b2", shown.first.strip
  end

  test "requests and errors are one count grouped by has_error, drawn per minute" do
    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[requests errors], "minutes" => 60)
    assert_equal({ "aggregation" => "count", "service" => "web", "groupBy" => "has_error", "requestType" => "time_series", "stepInterval" => 60, "timeRange" => "60m" },
                 metrics.arguments)

    at = Time.utc(2026, 10, 4, 10).to_i * 1000
    series = [ { "labels" => [ { "key" => { "name" => "has_error" }, "value" => false } ], "values" => [ { "timestamp" => at, "value" => 90 } ] },
               { "labels" => [ { "key" => { "name" => "has_error" }, "value" => true } ], "values" => [ { "timestamp" => at, "value" => 10 } ] } ]
    result = metrics.present_result(answer({ "data" => { "data" => { "results" => [ { "aggregations" => [ { "series" => series } ] } ] } } }))
    charts = result.dig("structuredContent", "charts")

    assert_equal [ "Requests of web", "Errors of web" ], charts.map { |chart| chart["title"] }
    assert_equal [ [ "2026-10-04T10:00:00Z", 100.0 ] ], charts.first["series"].first["points"]
    assert_equal [ [ "2026-10-04T10:00:00Z", 10.0 ] ], charts.last["series"].first["points"]
  end

  test "errors are failed spans counted by operation" do
    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web", "text" => "declined")

    assert_equal [ "count", true, "name", "scalar", "status_message CONTAINS 'declined'" ], errors.arguments.values_at("aggregation", "error", "groupBy", "requestType", "filter")
    scalar = { "data" => { "data" => { "results" => [ { "columns" => [ { "name" => "name" }, { "name" => "count()" } ], "data" => [ [ "POST /pay", 12 ] ] } ] } } }
    assert_match "POST /pay: 12 failed spans", errors.present_result(answer(scalar))["content"].first["text"]
  end

  test "what SigNoz does not keep is the platform's, and what it cannot read reaches the agent as it came" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu]).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build").environment_row
    assert_match "only requests and errors", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu], "connection" => "signoz")

    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web")
    assert_equal answer("not json"), logs.present_result(answer("not json"))
    failed = { "isError" => true, "content" => [ { "type" => "text", "text" => "key service.name not found" } ] }
    assert_equal failed, logs.present_result(failed)
  end

  test "a server whose tool lacks an argument Firefight writes is refused in words" do
    @row.integration.tools.find_by!(name: "signoz_search_logs").update!(params_schema: { "type" => "object", "properties" => { "query" => {} } })

    assert_match "takes its arguments in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "signoz")
  end
end
