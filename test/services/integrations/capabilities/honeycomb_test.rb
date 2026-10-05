require "test_helper"

class Integrations::Capabilities::HoneycombTest < ActiveSupport::TestCase
  include ObserverTestHelper

  setup do
    run_web_on_northflank
    @row = watch_with("honeycomb", "Honeycomb", { "run_query" => %w[environment_slug dataset_slug query_spec] }, fields: { "environment_slug" => "production" })
  end

  test "Honeycomb answers the slowest traces of a service in its environment, across every dataset, with relative time" do
    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "text" => "checkout", "minutes" => 30, "limit" => 5)

    assert_equal [ @row, "run_query" ], [ traces.environment_row, traces.tool.name ]
    assert_equal({ "environment_slug" => "production", "dataset_slug" => "__all__",
                   "query_spec" => { "calculations" => [ { "op" => "MAX", "column" => "duration_ms" } ],
                                     "filters" => [ { "column" => "service.name", "op" => "=", "value" => "web" }, { "column" => "name", "op" => "contains", "value" => "checkout" } ],
                                     "breakdowns" => [ "trace.trace_id", "name" ], "orders" => [ { "op" => "MAX", "column" => "duration_ms", "order" => "descending" } ],
                                     "limit" => 5, "time_range" => "30m" } }, traces.arguments)
    assert_nil traces.present
  end

  test "errors are failed spans by operation, and requests or errors one a call, with a start and end in Unix seconds" do
    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web")
    assert_includes errors.arguments.dig("query_spec", "filters"), { "column" => "error", "op" => "=", "value" => true }

    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[errors], "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")
    assert_equal [ 1_788_256_800, 1_788_260_400 ], metrics.arguments["query_spec"].values_at("start_time", "end_time")
    assert_equal %w[is_root error], metrics.arguments.dig("query_spec", "filters").drop(1).map { |filter| filter["column"] }
  end

  test "Honeycomb is passed over for what it does not answer, and a connection that does not know its environment answers nothing" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[requests cpu]).environment_row
    assert_match "does not search their text", unroutable(Integrations::Capabilities::ERRORS, "resource" => "web", "text" => "x")

    @row.update!(base_config: {})
    assert_match "no connection offers traces", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")
  end
end
