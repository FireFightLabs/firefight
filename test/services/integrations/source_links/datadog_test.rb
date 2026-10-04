require "test_helper"

module Integrations
  module SourceLinks
    class DatadogTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.new(workspace: workspaces(:slack_workspace_one), provider: "datadog", kind: Integration::KIND_MCP,
                                       settings: { "server_url" => "https://mcp.datadoghq.eu/v1/mcp", "region" => "eu1" })
      end

      test "a log search links to the Log Explorer on the site of the connection's region, with the same query and time" do
        travel_to Time.utc(2026, 9, 1, 12) do
          link = links.link(tool_name: "search_datadog_logs",
                            arguments: { "query" => "\"timeout\"", "service" => "web", "time_range" => { "from" => "now-15m", "to" => "now" } })

          assert_equal "Datadog", link.provider
          assert_equal "https://app.datadoghq.eu/logs?#{{ from_ts: 1_788_263_100_000, query: 'service:web "timeout"', to_ts: 1_788_264_000_000 }.to_query}", link.url
        end
      end

      test "a connection made by pasting its server's address is in the region that server is in" do
        @integration.settings = { "server_url" => "https://mcp.us5.datadoghq.com/api/unstable/mcp-server/mcp" }
        assert links.link(tool_name: "search_datadog_logs", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" }).url.start_with?("https://us5.datadoghq.com/logs?")

        @integration.settings = { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" }
        assert links.link(tool_name: "search_datadog_logs", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" }).url.start_with?("https://app.datadoghq.com/logs?")
      end

      test "every region links to its own site, and spans or a server in no region get no link" do
        IntegrationProvider.find("datadog").regions.each do |region|
          @integration.settings = { "server_url" => region.server_url, "region" => region.key }
          link = links.link(tool_name: "search_datadog_logs", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" })
          assert link.url.start_with?("#{region.site}/logs?"), "#{region.key} links to #{link.url}"
        end

        assert_nil links.link(tool_name: "search_datadog_spans", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" })
        @integration.settings = { "server_url" => "https://example.com/mcp" }
        assert_nil links.link(tool_name: "search_datadog_logs", arguments: { "query" => "*", "from" => "now-60m", "to" => "now" })
      end

      private

      def links = Datadog.new(ConnectionSettings.of(@integration.integration_environments.build))
    end
  end
end
