require "test_helper"

module Integrations
  class DiscoveryServiceTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    setup do
      @integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP,
        provider: "newrelic", name: "New Relic",
        settings: { "server_url" => "https://mcp.example/mcp" }
      )
      @integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
    end

    test "sync! upserts discovered tools disabled by default and disables vanished ones" do
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "logs.query", "description" => "Query logs",
          "inputSchema" => { "type" => "object" }, "annotations" => { "readOnlyHint" => true } },
        { "name" => "Dashboards Write", "description" => "Edit dashboards" }
      ])

      DiscoveryService.sync!(@integration)

      logs = @integration.tools.find_by!(name: "logs.query")
      assert logs.read_only?
      assert_not logs.enabled?
      assert_equal "logs.query", logs.remote_name

      sanitized = @integration.tools.find_by!(name: "dashboards_write")
      assert_equal "Dashboards Write", sanitized.remote_name
      assert_not sanitized.read_only?

      logs.update!(enabled: true)
      McpClient.any_instance.stubs(:tools_list).returns([])
      DiscoveryService.sync!(@integration)
      assert_not logs.reload.enabled?, "vanished tools are disabled, never deleted"
      assert Ability::Action.exists?(key: "new_relic.logs.query"), "action row survives"
    end

    test "health check records status" do
      row = @integration.integration_environments.first

      McpClient.any_instance.stubs(:ping).returns(true)
      assert HealthCheckService.check!(row)
      assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.reload.health_status

      McpClient.any_instance.stubs(:ping).raises(McpClient::Error, "down")
      assert_not HealthCheckService.check!(row)
      assert_equal IntegrationEnvironment::HEALTH_FAILING, row.reload.health_status
    end
  end
end
