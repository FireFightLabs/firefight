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

    test "sync! upserts discovered tools disabled by default and marks vanished ones removed" do
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
      logs.reload
      assert_not logs.available?, "vanished tools are marked removed, never deleted"
      assert logs.enabled?, "the admin's allowlist is not the provider's listing"
      assert_not logs.configured_for?({}), "a removed tool cannot be called"
      assert Ability::Action.exists?(key: "new_relic.logs.query"), "action row survives"

      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "logs.query", "description" => "Query logs" } ])
      DiscoveryService.sync!(@integration)
      assert logs.reload.available?, "a tool that comes back is offered again with its earlier choice"
      assert logs.enabled?
    end

    test "re-discovery that flips a tool to write updates the action's risk level" do
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "logs.query", "description" => "Query logs",
          "inputSchema" => { "type" => "object" }, "annotations" => { "readOnlyHint" => true } }
      ])
      DiscoveryService.sync!(@integration)

      tool = @integration.tools.find_by!(name: "logs.query")
      tool.update!(enabled: true)
      assert_equal Ability::Action::RISK_READ, tool.ability_action.risk_level

      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "logs.query", "description" => "Query and delete logs",
          "inputSchema" => { "type" => "object", "properties" => { "q" => { "type" => "string" } } } }
      ])
      DiscoveryService.sync!(@integration)

      action = tool.reload.ability_action.reload
      assert_equal Ability::Action::RISK_WRITE, action.risk_level
      assert_not action.reversible
      assert_equal tool.params_schema, action.params_schema
    end

    class FailingHealthPack < FakeNativePack
      def check_health!(environment_row)
        raise NativePack::Error, "credentials rejected"
      end
    end

    test "sync! reads a native integration's tools from its pack, same reconciliation semantics" do
      native = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "fake", name: "Fake Native"
      )
      leftover = native.tools.create!(name: "gone_tool", enabled: true)
      NativePack.stubs(:for).with("fake").returns(FakeNativePack)

      DiscoveryService.sync!(native)

      tool = native.tools.find_by!(name: "echo_text")
      assert tool.read_only?
      assert_not tool.enabled?, "pack tools arrive disabled like discovered ones"
      assert_equal "Echoes text back", tool.description
      assert_not leftover.reload.available?, "tools the pack no longer declares are marked removed"
    end

    test "native health check runs the pack probe and records failures readably" do
      native = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "fake", name: "Fake Native"
      )
      row = native.integration_environments.create!

      NativePack.stubs(:for).with("fake").returns(FakeNativePack)
      assert HealthCheckService.check!(row)
      assert_equal IntegrationEnvironment::HEALTH_HEALTHY, row.reload.health_status

      NativePack.stubs(:for).with("fake").returns(FailingHealthPack)
      assert_not HealthCheckService.check!(row)
      assert_equal IntegrationEnvironment::HEALTH_FAILING, row.reload.health_status
      assert_equal "credentials rejected", row.health_error
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
