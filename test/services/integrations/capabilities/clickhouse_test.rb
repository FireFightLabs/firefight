require "test_helper"

class Integrations::Capabilities::ClickhouseTest < ActiveSupport::TestCase
  ORGANIZATION = "6b3a2f1e-0000-4000-8000-000000000001".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    clickhouse = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "clickhouse", name: "ClickHouse", slug: "clickhouse",
                                                 settings: { "server_url" => "https://mcp.clickhouse.cloud/mcp" })
    @row = clickhouse.integration_environments.create!
    %w[run_select_query get_service_details].each do |name|
      clickhouse.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "clickhouse", account: ORGANIZATION, kind: ResourceMap::KIND_DATABASE,
                                  external_id: "svc-1", name: "analytics", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "status asks for the service's details in its organization, as ClickHouse documents the tool" do
    call = resolve(Integrations::Capabilities::STATUS, "resource" => "analytics")

    assert_equal [ @row, "get_service_details" ], [ call.environment_row, call.tool.name ]
    assert_equal({ "organizationId" => ORGANIZATION, "serviceId" => "svc-1" }, call.arguments)
    assert Integrations::Capabilities::Clickhouse.wraps?("get_service_details")
    assert_not Integrations::Capabilities::Clickhouse.wraps?("run_select_query")
  end

  test "logs read what the server printed, or the queries clients sent, with every filter a quoted literal" do
    printed = resolve(Integrations::Capabilities::LOGS, "resource" => "analytics", "text" => "it's \\ odd", "regex" => "Code: \\d+", "minutes" => 30)
    sql = printed.arguments["query"]

    assert_equal "svc-1", printed.arguments["serviceId"]
    assert_includes sql, "FROM clusterAllReplicas('default', merge('system', '^text_log'))"
    assert_includes sql, "position(message, 'it\\'s \\\\ odd') > 0"
    assert_includes sql, "match(message, 'Code: \\\\d+')"
    assert_includes sql, "event_time >= now() - INTERVAL 30 MINUTE"
    assert_includes sql, "LIMIT 200"

    queries = resolve(Integrations::Capabilities::LOGS, "resource" => "analytics", "stream" => "requests", "limit" => 20).arguments["query"]
    assert_includes queries, "merge('system', '^query_log')"
    assert_includes queries, "is_initial_query = 1"
    assert_includes queries, "LIMIT 20"
    assert_match "stream app", unroutable(Integrations::Capabilities::LOGS, "resource" => "analytics", "stream" => "build")
    assert_match "under 500 characters", unroutable(Integrations::Capabilities::LOGS, "resource" => "analytics", "text" => "x" * 501)
  end

  test "an absolute range is written as times in UTC, so the same request reads the same rows" do
    sql = resolve(Integrations::Capabilities::ERRORS, "resource" => "analytics", "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T11:00:00Z").arguments["query"]

    assert_includes sql, "event_time >= toDateTime('2026-10-01 10:00:00', 'UTC') AND event_time <= toDateTime('2026-10-01 11:00:00', 'UTC')"
    assert_includes sql, "exception_code != 0"
    assert_includes sql, "GROUP BY exception_code ORDER BY times DESC"
  end

  test "metrics come back as a chart per metric with a series per replica, in the units the capability names" do
    travel_to Time.utc(2026, 10, 1, 12) do
      call = resolve(Integrations::Capabilities::METRICS, "resource" => "analytics", "metrics" => %w[requests memory cpu], "minutes" => 60)
      assert_includes call.arguments["query"], "sum(ProfileEvent_Query) AS requests"
      assert_includes call.arguments["query"], "avg(CurrentMetric_MemoryTracking) AS memory"

      rows = [ [ "2026-10-01 11:30:00", "replica-0", 120, 2_097_152, 30_000_000 ], [ "2026-10-01 11:31:00", "replica-0", 60, 1_048_576, 60_000_000 ],
               [ "2026-10-01 11:30:00", "replica-1", 30, 1_048_576, 0 ] ]
      answer = call.present_result(text({ "columns" => %w[at replica requests memory cpu], "rows" => rows }))
      charts = answer.dig("structuredContent", "charts")

      assert_equal [ "Queries of analytics", "Memory of analytics", "CPU of analytics" ], charts.map { |chart| chart["title"] }
      assert_equal %w[replica-0 replica-1], charts.first["series"].map { |series| series["label"] }
      assert_equal [ 120.0, 60.0 ], charts.first["series"].first["points"].map(&:last)
      assert_equal [ 2.0, 1.0 ], charts.second["series"].first["points"].map(&:last)
      assert_equal [ 0.5, 1.0 ], charts.third["series"].first["points"].map(&:last)
      assert_equal %w[per\ minute MB vCPU], charts.map { |chart| chart["unit"] }
    end
    assert_match "does not keep disk", unroutable(Integrations::Capabilities::METRICS, "resource" => "analytics", "metrics" => [ "disk" ])
  end

  test "logs and errors read the rows back into lines, and an answer in another shape reaches the agent as it came" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "analytics")
    lines = logs.present_result(text([ { "at" => "2026-10-01 11:30:00.123456", "replica" => "replica-0", "level" => "Error",
                                        "logger_name" => "MergeTreeBackgroundExecutor", "message" => "Code: 241. Memory limit exceeded" } ]))
    assert_match "replica-0 Error MergeTreeBackgroundExecutor: Code: 241. Memory limit exceeded", lines["content"].first["text"]

    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "analytics")
    grouped = errors.present_result(text({ "data" => [ { "error" => "MEMORY_LIMIT_EXCEEDED", "code" => 241, "times" => 12, "first_seen" => "2026-10-01 11:00:00",
                                                          "last_seen" => "2026-10-01 11:29:00", "example" => "Code: 241. DB::Exception" } ] }))
    assert_match "MEMORY_LIMIT_EXCEEDED (code 241): 12 times", grouped["content"].first["text"]
    assert_match "No query failed", errors.present_result(text([]))["content"].first["text"]

    odd = { "content" => [ { "type" => "text", "text" => "Service is waking up" } ] }
    assert_equal odd, errors.present_result(odd)
    refused = { "isError" => true, "content" => [ { "type" => "text", "text" => "Not enabled" } ] }
    assert_equal refused, logs.present_result(refused)
  end

  private

  def text(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
