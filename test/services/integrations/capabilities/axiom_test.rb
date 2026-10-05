require "test_helper"

class Integrations::Capabilities::AxiomTest < ActiveSupport::TestCase
  include ObserverTestHelper

  setup do
    run_web_on_northflank
    @row = watch_with("axiom", "Axiom", { "querydataset" => %w[apl startTime endTime] },
                      fields: { "org_id" => "acme", "logs_dataset" => "logs", "traces_dataset" => "otel-traces" })
  end

  test "Axiom answers logs from the logs dataset by service.name, with relative time" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "say \"hi\"", "minutes" => 15)

    assert_equal [ @row, "querydataset" ], [ logs.environment_row, logs.tool.name ]
    assert_equal({ "apl" => "['logs'] | where ['service.name'] == \"web\" | search \"say \\\"hi\\\"\" | sort by _time desc | take 200",
                   "startTime" => "now-15m", "endTime" => "now" }, logs.arguments)
    assert_equal [ @northflank_row, "search_logs" ], [ logs.fallback.environment_row, logs.fallback.tool.name ]
  end

  test "traces, errors and request counts come from the traces dataset" do
    assert_match "['otel-traces'] | where ['service.name'] == \"web\" | sort by error desc, duration desc | take 50",
                 resolve(Integrations::Capabilities::TRACES, "resource" => "web").arguments["apl"]
    assert_match "and error == true | summarize count(), first_seen = min(_time), last_seen = max(_time) by name, ['status.message']",
                 resolve(Integrations::Capabilities::ERRORS, "resource" => "web").arguments["apl"]
    assert_match "isnull(parent_span_id) | summarize count() by bin(_time, 60s), error",
                 resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[requests]).arguments["apl"]
  end

  test "a tool that takes no time arguments gets the range in the APL, and one whose query argument is unknown is refused" do
    @row.integration.tools.find_by!(name: "querydataset").update!(params_schema: { "type" => "object", "properties" => { "query" => {} } })
    asked = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")
    assert_equal "['otel-traces'] | where _time between (datetime(2026-09-01T10:00:00Z) .. datetime(2026-09-01T11:00:00Z)) | where ['service.name'] == \"web\" " \
                 "| sort by error desc, duration desc | take 50 | project _time, trace_id, name, duration, error, ['status.message']", asked.arguments["query"]

    @row.integration.tools.find_by!(name: "querydataset").update!(params_schema: { "type" => "object", "properties" => { "q" => {} } })
    assert_match "takes its query in a way Firefight does not know", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")
  end

  test "a connection without a traces dataset answers only logs, and a regular expression is the platform's" do
    @row.store_fields!({ "org_id" => "acme", "logs_dataset" => "logs" })

    assert_match "no connection offers traces", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")
    assert_equal @row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "time.?out").environment_row
    assert_match "Firefight searches Axiom by text", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "x", "connection" => "axiom")
  end
end
