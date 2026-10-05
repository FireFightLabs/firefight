require "test_helper"

module Integrations
  module SourceLinks
    class DatadogTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.new(workspace: workspaces(:slack_workspace_one), provider: "datadog",
                                       settings: { "server_url" => "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp" })
      end

      test "a log search links to the Log Explorer on the connection's site, with the same query and time" do
        travel_to Time.utc(2026, 9, 1, 12) do
          link = Datadog.new(@integration).link(tool_name: "search_datadog_logs",
                                                arguments: { "query" => "\"timeout\"", "service" => "web", "time_range" => { "from" => "now-15m", "to" => "now" } })

          assert_equal "Datadog", link.provider
          assert_equal "https://app.datadoghq.eu/logs?#{{ from_ts: 1_788_263_100_000, query: 'service:web "timeout"', to_ts: 1_788_264_000_000 }.to_query}", link.url
        end
      end

      test "a site that is its own host keeps it, and spans, errors or an unknown server get no link" do
        @integration.settings = { "server_url" => "https://mcp.us5.datadoghq.com/api/unstable/mcp-server/mcp" }
        link = Datadog.new(@integration).link(tool_name: "search_datadog_logs", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" })
        assert link.url.start_with?("https://us5.datadoghq.com/logs?")

        assert_nil Datadog.new(@integration).link(tool_name: "search_datadog_spans", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" })
        @integration.settings = { "server_url" => "https://example.com/mcp" }
        assert_nil Datadog.new(@integration).link(tool_name: "search_datadog_logs", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" })
      end
    end
  end
end
