require "test_helper"

class Integrations::Capabilities::LogfireTest < ActiveSupport::TestCase
  include ObserverTestHelper

  setup do
    run_web_on_northflank
    @row = watch_with("logfire", "Logfire", { "query_run" => %w[query project min_timestamp max_timestamp] })
  end

  test "Logfire answers logs by service_name in one SQL query, over whole minutes, and Northflank its status" do
    travel_to Time.utc(2026, 10, 4, 10, 0, 30) do
      logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "it's", "exclude" => "health", "minutes" => 30)

      assert_equal [ @row, "query_run" ], [ logs.environment_row, logs.tool.name ]
      assert_equal "SELECT start_timestamp, level_name(level) AS level, span_name, message FROM records WHERE service_name = 'web' " \
                   "AND strpos(message, 'it''s') > 0 AND strpos(message, 'health') = 0 ORDER BY start_timestamp DESC LIMIT 200", logs.arguments["query"]
      assert_equal %w[2026-10-04T09:31:00Z 2026-10-04T10:01:00Z], logs.arguments.values_at("min_timestamp", "max_timestamp")
      assert_equal [ @northflank_row, "search_logs" ], [ logs.fallback.environment_row, logs.fallback.tool.name ]
    end
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
  end

  test "rows read into log lines whether they come as a list, under rows or as columns" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web")
    row = { "start_timestamp" => "2026-10-04T10:00:00Z", "level" => "error", "message" => "timeout calling db" }
    columns = { "columns" => [ { "name" => "start_timestamp", "values" => [ row["start_timestamp"] ] }, { "name" => "level", "values" => [ "error" ] },
                               { "name" => "message", "values" => [ row["message"] ] } ] }

    [ [ row ], { "rows" => [ row ] }, columns ].each do |body|
      assert_match "2026-10-04T10:00:00Z error timeout calling db", logs.present_result(answer(body))["content"].first["text"]
    end
    assert_equal answer({ "rows" => [] }), logs.present_result(answer({ "rows" => [] }))
  end

  test "exceptions are grouped by type, and traces put failed spans first" do
    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web")
    assert_match "WHERE service_name = 'web' AND is_exception GROUP BY exception_type ORDER BY last_seen DESC LIMIT 50", errors.arguments["query"]
    shown = errors.present_result(answer([ { "exception_type" => "TimeoutError", "example" => "db", "occurrences" => 4, "first_seen" => "a", "last_seen" => "b" } ]))
    assert_match "TimeoutError: 4 times, first a, last b. db", shown["content"].first["text"]

    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web")
    assert_match "ORDER BY (otel_status_code = 'ERROR' OR is_exception) DESC, duration DESC LIMIT 50", traces.arguments["query"]
    span = { "trace_id" => "abc", "start_timestamp" => "2026-10-04T10:00:00Z", "span_name" => "GET /", "duration" => 1.5, "otel_status_code" => "ERROR" }
    assert_match "trace abc, GET /, 1500.0 ms, failed", traces.present_result(answer([ span ]))["content"].first["text"]
  end

  test "metrics come from records and the metrics table in one query and draw a chart each" do
    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[requests cpu], "minutes" => 60)

    assert_match "count(*) / 1.0 AS value FROM records WHERE service_name IN ('web') AND http_response_status_code IS NOT NULL", metrics.arguments["query"]
    assert_match "avg(scalar_value) * 100 AS value FROM metrics WHERE service_name IN ('web') AND metric_name = 'process.cpu.utilization'", metrics.arguments["query"]
    rows = [ { "bucket" => "2026-10-04T10:00:00Z", "service_name" => "web", "metric" => "requests", "value" => 12 },
             { "bucket" => "2026-10-04T10:00:00Z", "service_name" => "web", "metric" => "cpu", "value" => 41.5 } ]
    charts = metrics.present_result(answer(rows)).dig("structuredContent", "charts")

    assert_equal [ [ "Requests of web", "per minute" ], [ "CPU of web", "%" ] ], charts.map { |chart| chart.values_at("title", "unit") }
    assert_equal [ [ "2026-10-04T10:00:00Z", 41.5 ] ], charts.last["series"].first["points"]
  end

  test "what Logfire does not keep the same way everywhere is the platform's" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[memory]).environment_row
    assert_match "Logfire keeps only", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[memory], "connection" => "logfire")
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build", "connection" => "logfire")
    @row.integration.tools.find_by!(name: "query_run").update!(params_schema: { "type" => "object", "properties" => { "sql" => {} } })
    assert_match "does not know (no query, min_timestamp, max_timestamp)", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "logfire")
  end

  test "a site's errors come from Logfire too, since a frontend's errors come from the site that serves it" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SITE, external_id: "shop-id",
                                  name: "shop", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)

    assert_equal @row, resolve(Integrations::Capabilities::ERRORS, "resource" => "shop").environment_row
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "shop")
  end
end
