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

    test "a tool the provider's entry names as read only is a read, whatever the server says" do
      @integration.update!(provider: "cloudflare", settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "search", "description" => "Search the API spec", "annotations" => { "readOnlyHint" => false } },
        { "name" => "execute", "description" => "Call the API", "annotations" => { "readOnlyHint" => false, "destructiveHint" => true } }
      ])

      DiscoveryService.sync!(@integration)

      assert @integration.tools.find_by!(name: "search").read_only?
      assert_not @integration.tools.find_by!(name: "execute").read_only?
    end

    test "a tool its server marks read only is a change, still switched on, unless the registry lists it as a read" do
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "drop_account", "annotations" => { "readOnlyHint" => true } },
        { "name" => "get_entity", "annotations" => { "readOnlyHint" => false } }
      ])

      DiscoveryService.sync!(@integration)

      claimed = @integration.tools.find_by!(name: "drop_account")
      assert_not claimed.read_only?, "a server's own word never makes a tool a read"
      assert_not claimed.declared_read?
      assert claimed.enabled?, "only its classification changes, it still arrives switched on"
      assert_equal Ability::Action::RISK_WRITE, claimed.ability_action.risk_level
      assert @integration.tools.find_by!(name: "get_entity").read_only?, "a read the registry lists stays a read"
    end

    test "a tool the server marks read only that the registry says sends something is a change" do
      @integration.update!(provider: "posthog", settings: { "server_url" => "https://mcp.posthog.com/mcp?mode=tools" })
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "agent-feedback", "annotations" => { "readOnlyHint" => true } },
        { "name" => "loops-create-prepare", "annotations" => { "readOnlyHint" => true } },
        { "name" => "insight-get", "annotations" => { "readOnlyHint" => true } }
      ])

      DiscoveryService.sync!(@integration)

      assert_not @integration.tools.find_by!(name: "agent_feedback").read_only?
      assert_not @integration.tools.find_by!(name: "loops_create_prepare").read_only?
      assert @integration.tools.find_by!(name: "insight_get").read_only?
    end

    test "a tool an admin marked as a read stays one through a refresh, and unmarking it makes it a change again" do
      @integration.update!(provider: "custom_mcp", settings: { "server_url" => "https://tools.acme.example/mcp" })
      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "query_logs" }, { "name" => "status", "annotations" => { "readOnlyHint" => true } } ])
      DiscoveryService.sync!(@integration)
      tool = @integration.tools.find_by!(name: "query_logs")
      assert_not tool.read_only?

      tool.mark_read!(true)
      DiscoveryService.sync!(@integration)
      assert tool.reload.read_only?
      assert_equal Ability::Action::RISK_READ, tool.ability_action.risk_level

      tool.mark_read!(false)
      assert_not tool.reload.read_only?
      assert_equal Ability::Action::RISK_WRITE, tool.ability_action.reload.risk_level
      status = @integration.tools.find_by!(name: "status")
      assert_not status.read_only?, "the server's own mark is not a read"
      assert status.read_markable?, "so an admin can mark it"
    end

    test "sync! upserts discovered tools switched on and marks vanished ones removed" do
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "get_entity", "description" => "Query logs",
          "inputSchema" => { "type" => "object" }, "annotations" => { "readOnlyHint" => true } },
        { "name" => "Dashboards Write", "description" => "Edit dashboards" }
      ])

      DiscoveryService.sync!(@integration)

      logs = @integration.tools.find_by!(name: "get_entity")
      assert logs.read_only?
      assert logs.enabled?, "a new tool arrives switched on"
      assert_equal "get_entity", logs.remote_name

      sanitized = @integration.tools.find_by!(name: "dashboards_write")
      assert_equal "Dashboards Write", sanitized.remote_name
      assert_not sanitized.read_only?
      assert sanitized.enabled?, "a tool that changes something arrives switched on too"

      McpClient.any_instance.stubs(:tools_list).returns([])
      DiscoveryService.sync!(@integration)
      logs.reload
      assert_not logs.available?, "vanished tools are marked removed, never deleted"
      assert logs.enabled?, "the admin's allowlist is not the provider's listing"
      assert_not logs.configured_for?({}), "a removed tool cannot be called"
      assert Ability::Action.exists?(key: "new_relic.get_entity"), "action row survives"

      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "get_entity", "description" => "Query logs" } ])
      DiscoveryService.sync!(@integration)
      assert logs.reload.available?, "a tool that comes back is offered again with its earlier choice"
      assert logs.enabled?
    end

    test "a tool already known keeps the admin's choice, and one discovered later on the same connection arrives switched on" do
      @integration.tools.create!(name: "logs.query", read_only: true, enabled: false)
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "logs.query", "annotations" => { "readOnlyHint" => true } },
        { "name" => "alerts.mute", "description" => "Mute an alert" }
      ])

      DiscoveryService.sync!(@integration)

      assert_not @integration.tools.find_by!(name: "logs.query").enabled?, "a tool switched off stays off"
      muted = @integration.tools.find_by!(name: "alerts.mute")
      assert muted.enabled?
      packs = @integration.permission_packs.index_by(&:pack)
      assert_equal [ muted.ability_action ], packs[Ability::Role::PACK_CHANGES].actions.to_a
      assert_equal [ muted.ability_action ], packs[Ability::Role::PACK_EVERYTHING].actions.to_a
      assert_empty packs[Ability::Role::PACK_READ].actions
    end

    test "a new tool Halon would call by another connection's tool's name stays off" do
      other = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: "newrelic",
                                  name: "New", settings: { "server_url" => "https://mcp.example/other" })
      other.tools.create!(name: "relic_logs", read_only: true, enabled: true)
      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "logs", "annotations" => { "readOnlyHint" => true } } ])

      DiscoveryService.sync!(@integration)

      assert_equal "new_relic_logs", @integration.tools.find_by!(name: "logs").model_facing_name
      assert_not @integration.tools.find_by!(name: "logs").enabled?
    end

    test "re-discovery that finds a tool is no longer a listed read updates the action's risk level" do
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "get_entity", "description" => "Read an entity", "inputSchema" => { "type" => "object" } }
      ])
      DiscoveryService.sync!(@integration)

      tool = @integration.tools.find_by!(name: "get_entity")
      assert_equal Ability::Action::RISK_READ, tool.ability_action.risk_level

      IntegrationProvider::Entry.any_instance.stubs(:read_only_tools).returns([])
      McpClient.any_instance.stubs(:tools_list).returns([
        { "name" => "get_entity", "description" => "Read and delete an entity",
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
      assert tool.enabled?, "pack tools arrive switched on like discovered ones"
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

    test "a server's tools are saved together in one transaction, so a failure part way saves none of them" do
      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "first" }, { "name" => "second" } ])
      Ability::Action.stubs(:insert_all!).raises(ActiveRecord::RecordInvalid)

      assert_raises(ActiveRecord::RecordInvalid) { DiscoveryService.sync!(@integration) }
      assert_empty @integration.tools.reload, "no tool is left saved without its ability"
    end

    test "a failure filing the new actions in their packs leaves no tool or action saved" do
      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "first" } ])
      Ability::Role.stubs(:file_waiting).raises(ActiveRecord::RecordInvalid)

      assert_raises(ActiveRecord::RecordInvalid) { DiscoveryService.sync!(@integration) }
      assert_empty @integration.tools.reload
      assert_not Ability::Action.exists?(key: "new_relic.first")
    end

    test "every new tool Halon would call by another connection's tool's name arrives switched off, two of them spelled apart included" do
      other = Integration.create!(workspace: @integration.workspace, kind: Integration::KIND_MCP, provider: Integration::PROVIDER_CUSTOM_MCP,
                                  name: "New Relic EU", settings: { "server_url" => "https://mcp.eu.example/mcp" })
      other.update_columns(slug: "new")
      other.tools.create!(name: "relic_logs_query", enabled: true)
      McpClient.any_instance.stubs(:tools_list).returns([ { "name" => "logs.query" }, { "name" => "logs_query" }, { "name" => "status" } ])

      DiscoveryService.sync!(@integration)

      assert_equal({ "logs.query" => false, "logs_query" => false, "status" => true }, @integration.tools.reload.to_h { |tool| [ tool.name, tool.enabled ] })
    end

    test "a server's new tools and their abilities are saved in the same queries however many it lists" do
      extend ManyToolsHelper
      per_tool = [ 10, 40 ].map do |count|
        integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: Integration::PROVIDER_CUSTOM_MCP,
                                          name: "Server #{count}", settings: { "server_url" => "https://mcp#{count}.example/mcp" })
        integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
        McpClient.any_instance.stubs(:tools_list).returns(Array.new(count) { |index| { "name" => "tool_#{index}", "annotations" => { "readOnlyHint" => index.even? } } })
        queries = queries_made { DiscoveryService.sync!(integration) }
        assert_equal count, integration.tools.enabled.count
        assert_equal count, Ability::Action.where(source: integration.tools).count
        queries
      end

      slope = (per_tool.last - per_tool.first) / 30.0
      assert_operator slope, :<, 0.5, "each new tool took #{slope.round(1)} queries"
    end
  end
end
