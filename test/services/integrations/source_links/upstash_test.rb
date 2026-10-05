require "test_helper"

module Integrations
  module SourceLinks
    class UpstashTest < ActiveSupport::TestCase
      setup do
        integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash",
                                                                            settings: { "server_url" => "https://mcp.upstash.com/mcp" })
        @settings = ConnectionSettings.of(integration.integration_environments.create!)
      end

      test "a result opens the console page of its product, on the console the registry names" do
        builder = Upstash.new(@settings)

        assert_equal "https://console.upstash.com/redis", builder.link(tool_name: "redis_get_stats", arguments: {}).url
        assert_equal "https://console.upstash.com/qstash", builder.link(tool_name: "qstash_list_schedules", arguments: { "region" => "eu" }).url
        assert_equal "https://console.upstash.com/qstash", builder.link(tool_name: "logs_list", arguments: { "service" => "qstash" }).url
        assert_equal "https://console.upstash.com/workflow", builder.link(tool_name: "dlq_list", arguments: { "service" => "workflow" }).url
        assert_equal "https://console.upstash.com/workflow", builder.link(tool_name: "workflow_manage_run", arguments: {}).url
        assert_equal "the Upstash console", builder.link(tool_name: "redis_list_databases", arguments: {}).provider
        assert_nil builder.link(tool_name: "index_list", arguments: {})
        assert_nil Upstash.new(nil).link(tool_name: "redis_get_stats", arguments: {})
      end
    end
  end
end
