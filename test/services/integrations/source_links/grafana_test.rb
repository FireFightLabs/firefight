require "test_helper"

module Integrations
  module SourceLinks
    class GrafanaTest < ActiveSupport::TestCase
      setup do
        workspace = workspaces(:slack_workspace_one)
        @integration = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana", slug: "grafana",
                                                      settings: { "server_url" => "https://mcp-grafana.acme.dev/mcp" })
        @row = @integration.integration_environments.create!(base_config: { "learned" => {
          "address" => "https://acme.grafana.net/grafana",
          "datasources" => [ { "uid" => "loki-uid", "name" => "Loki", "type" => "loki", "default" => false } ]
        } })
      end

      test "a Loki query links to Explore on the same query over the same time, as Grafana documents its Explore address" do
        travel_to Time.utc(2026, 9, 1, 12) do
          link = Grafana.new(settings).link(tool_name: "query_loki_logs",
                                                      arguments: { "datasourceUid" => "loki-uid", "logql" => "{service_name=\"web\"} |= \"timeout\"",
                                                                   "startRfc3339" => "now-15m", "endRfc3339" => "now" })

          pane = { "a" => { "datasource" => "loki-uid",
                            "queries" => [ { "refId" => "A", "datasource" => { "uid" => "loki-uid", "type" => "loki" }, "expr" => "{service_name=\"web\"} |= \"timeout\"" } ],
                            "range" => { "from" => "1788263100000", "to" => "1788264000000" } } }
          assert_equal "Grafana", link.provider
          assert_equal "https://acme.grafana.net/grafana/explore?#{{ panes: pane.to_json, schemaVersion: 1 }.to_query}", link.url
        end
      end

      test "Prometheus and Tempo queries carry their own query fields, and an absolute time reads as it was asked" do
        prometheus = Grafana.new(settings).link(tool_name: "query_prometheus",
                                                          arguments: { "datasourceUid" => "prom-uid", "expr" => "up", "startTime" => "2026-09-01T10:00:00Z", "endTime" => "2026-09-01T11:00:00Z" })
        tempo = Grafana.new(settings).link(tool_name: "search_tempo_traces", arguments: { "datasourceUid" => "tempo-uid", "query" => "{ status = error }" })

        prometheus_pane = JSON.parse(Rack::Utils.parse_query(URI.parse(prometheus.url).query)["panes"])["a"]
        assert_equal({ "refId" => "A", "datasource" => { "uid" => "prom-uid" }, "expr" => "up" }, prometheus_pane["queries"].sole)
        assert_equal({ "from" => "1788256800000", "to" => "1788260400000" }, prometheus_pane["range"])
        tempo_query = JSON.parse(Rack::Utils.parse_query(URI.parse(tempo.url).query)["panes"])["a"]["queries"].sole
        assert_equal [ "traceql", "{ status = error }" ], tempo_query.values_at("queryType", "query")
        trace = Grafana.new(settings).link(tool_name: "get_tempo_trace", arguments: { "datasourceUid" => "tempo-uid", "trace_id" => "2f3e0cee77ae5dc9" })
        assert_equal "2f3e0cee77ae5dc9", JSON.parse(Rack::Utils.parse_query(URI.parse(trace.url).query)["panes"])["a"]["queries"].sole["query"]
        patterns = Grafana.new(settings).link(tool_name: "query_loki_patterns", arguments: { "datasourceUid" => "loki-uid", "logql" => "{app=\"web\"}" })
        assert_equal "{app=\"web\"}", JSON.parse(Rack::Utils.parse_query(URI.parse(patterns.url).query)["panes"])["a"]["queries"].sole["expr"]
      end

      test "there is no link without Grafana's address, a datasource or a query, or for a tool that reads no datasource" do
        arguments = { "datasourceUid" => "loki-uid", "logql" => "{app=\"web\"}" }

        assert_nil Grafana.new(nil).link(tool_name: "query_loki_logs", arguments: arguments)
        assert_nil Grafana.new(settings).link(tool_name: "query_loki_logs", arguments: arguments.except("datasourceUid"))
        assert_nil Grafana.new(settings).link(tool_name: "search_dashboards", arguments: { "query" => "web" })
        @row.update!(base_config: { "learned" => { "datasources" => [] } })
        assert_nil Grafana.new(settings).link(tool_name: "query_loki_logs", arguments: arguments)
      end

      test "the executor adds the Explore link to what Grafana answered, and nothing to an error" do
        tool = @integration.tools.create!(name: "query_loki_logs", description: "Logs", params_schema: {}, spec: { "tool_name" => "query_loki_logs" })
        McpClient.any_instance.stubs(:call_tool).returns({ "content" => [ { "type" => "text", "text" => { "data" => [] }.to_json } ] })

        result = McpExecutor.call(tool: tool, environment_row: @row, arguments: { "datasourceUid" => "loki-uid", "logql" => "{app=\"web\"}" })
        assert result["content"].last["text"].start_with?("Open this in Grafana, and give the person this link with what you found: https://acme.grafana.net/grafana/explore?")

        McpClient.any_instance.stubs(:call_tool).returns({ "isError" => true, "content" => [ { "type" => "text", "text" => "datasource not found" } ] })
        assert_equal 1, McpExecutor.call(tool: tool, environment_row: @row, arguments: { "datasourceUid" => "loki-uid", "logql" => "{app=\"web\"}" })["content"].size
      end

      private

      def settings = ConnectionSettings.of(@row.reload)
    end
  end
end
