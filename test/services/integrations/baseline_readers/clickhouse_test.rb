require "test_helper"

module Integrations
  module BaselineReaders
    class ClickhouseTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "clickhouse", name: "ClickHouse",
                                                       settings: { "server_url" => "https://mcp.clickhouse.cloud/mcp" })
        @row = @integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
        @tool = @integration.tools.create!(name: "run_select_query", enabled: true, read_only: true)
        ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
          ResourceMap::Found.new(provider: "clickhouse", account: "org", kind: ResourceMap::KIND_DATABASE, external_id: "svc-1", name: "analytics")
        ]))
        @service = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "svc-1")
      end

      test "a week of metric_log is read hour by hour, the replicas added up, through the switched on query tool" do
        now = Time.utc(2026, 10, 1, 5)
        rows = [ { "at" => "2026-09-30 10:00:00", "replica" => "r0", "requests" => 600, "errors" => 6, "cpu" => 1_800_000_000, "memory" => 1_048_576 },
                 { "at" => "2026-09-30 10:00:00", "replica" => "r1", "requests" => 1200, "errors" => 0, "cpu" => 0, "memory" => 1_048_576 } ]
        McpClient.any_instance.expects(:call_tool).with do |name:, arguments:|
          name == "run_select_query" && arguments["serviceId"] == "svc-1" && arguments["query"].include?("INTERVAL 60 MINUTE") &&
            arguments["query"].include?("toDateTime('2026-09-24 05:00:00', 'UTC')")
        end.returns({ "content" => [ { "type" => "text", "text" => rows.to_json } ] })

        found = McpExecutor.baselines_of(@row, [ @service ], (now - 7.days)..now)

        assert_equal({ "requests" => 30.0, "errors" => 0.1, "cpu" => 0.5, "memory" => 2.0 }, found.to_h { |reading| [ reading.metric, reading.points.sole.last ] })
        assert_equal [ "Queries", "per minute" ], found.first.to_h.values_at(:label, :unit)
        assert_equal Ability::Invocation::OUTCOME_SUCCESS, Ability::Invocation.find_by!(action_key: @tool.action_key).outcome
      end

      test "a service ClickHouse refuses keeps its baselines, and a switched off tool reads nothing" do
        McpClient.any_instance.stubs(:call_tool).returns({ "isError" => true, "content" => [ { "type" => "text", "text" => "UNKNOWN_TABLE" } ] })
        assert_empty McpExecutor.baselines_of(@row, [ @service ], 7.days.ago..Time.current)

        @tool.update!(enabled: false)
        assert_nil McpExecutor.baselines_of(@row, [ @service ], 7.days.ago..Time.current)
      end
    end
  end
end
