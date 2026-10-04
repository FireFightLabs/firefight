require "test_helper"

module Integrations
  module HealthProbes
    class GrafanaTest < ActiveSupport::TestCase
      # list_datasources answers as grafana/mcp-grafana writes it (tools/datasources.go, ListDatasourcesResult).
      LISTED = { "datasources" => [
        { "id" => 1, "uid" => "loki-uid", "name" => "Loki", "type" => "loki", "isDefault" => false },
        { "id" => 2, "uid" => "prom-uid", "name" => "Prometheus", "type" => "prometheus", "isDefault" => true },
        { "id" => 3, "uid" => "tempo-uid", "name" => "Tempo", "type" => "tempo", "isDefault" => false },
        { "id" => 4, "uid" => "pg-uid", "name" => "Postgres", "type" => "grafana-postgresql-datasource", "isDefault" => false }
      ], "total" => 4, "hasMore" => false }.freeze
      DEEPLINK = "https://acme.grafana.net/explore?panes=%7B%7D&schemaVersion=1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana", slug: "grafana",
                                                       settings: { "server_url" => "https://mcp-grafana.acme.dev/mcp" })
        @row = @integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
        @list = tool("list_datasources")
        @deeplink = tool("generate_deeplink")
        McpClient.any_instance.stubs(:ping).returns(true)
      end

      test "the health check lists Grafana's datasources, keeps the ones Firefight reads, and learns Grafana's address once" do
        McpClient.any_instance.expects(:call_tool).with(name: "list_datasources", arguments: { "limit" => 100, "offset" => 0 }).twice.returns(answer(LISTED))
        McpClient.any_instance.expects(:call_tool).with(name: "generate_deeplink", arguments: { "resourceType" => "explore", "datasourceUid" => "loki-uid" })
                 .once.returns({ "content" => [ { "type" => "text", "text" => DEEPLINK } ] })

        assert HealthCheckService.check!(@row)
        assert HealthCheckService.check!(@row)

        @row.reload
        assert_equal IntegrationEnvironment::HEALTH_HEALTHY, @row.health_status
        assert_equal %w[loki-uid prom-uid tempo-uid], @row.learned["datasources"].map { |source| source["uid"] }
        assert_equal "https://acme.grafana.net", Grafana.address(ConnectionSettings.of(@row))
        assert_equal "prom-uid", Grafana.datasource(ConnectionSettings.of(@row), Grafana::PROMETHEUS)["uid"]
        assert_equal [ { "value" => "loki-uid", "label" => "Loki" } ], @row.learned["loki"]
        assert_equal [ { "value" => "tempo-uid", "label" => "Tempo" } ], @row.learned["tempo"]
        logged = Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_HEALTH_CHECK)
        assert_equal 3, logged.count
        assert_equal [ SystemAgent.health_check ], logged.map(&:principal).uniq
      end

      test "Grafana's refusal marks the connection failing in its own words" do
        McpClient.any_instance.stubs(:call_tool).returns({ "isError" => true, "content" => [ { "type" => "text", "text" => "list datasources: 401 Unauthorized" } ] })

        assert_not HealthCheckService.check!(@row)
        assert_equal "Grafana refused list_datasources: list datasources: 401 Unauthorized.", @row.reload.health_error
      end

      test "with list_datasources switched off the ping alone decides, and nothing is learned or called" do
        @list.update!(enabled: false)
        McpClient.any_instance.expects(:call_tool).never

        assert HealthCheckService.check!(@row)
        assert_empty @row.reload.learned
      end

      test "every page of datasources is read, and without generate_deeplink there is no address rather than a guess" do
        @deeplink.update!(enabled: false)
        first = LISTED.merge("datasources" => LISTED["datasources"].first(1), "hasMore" => true)
        second = LISTED.merge("datasources" => LISTED["datasources"].drop(1))
        McpClient.any_instance.stubs(:call_tool).with(name: "list_datasources", arguments: { "limit" => 100, "offset" => 0 }).returns(answer(first))
        McpClient.any_instance.stubs(:call_tool).with(name: "list_datasources", arguments: { "limit" => 100, "offset" => 100 }).returns(answer(second))

        assert HealthCheckService.check!(@row)
        assert_equal 3, @row.reload.learned["datasources"].size
        assert_nil Grafana.address(ConnectionSettings.of(@row))
      end

      test "an address that is not Grafana's own web address is not kept" do
        McpClient.any_instance.stubs(:call_tool).with(name: "list_datasources", arguments: anything).returns(answer(LISTED))
        McpClient.any_instance.stubs(:call_tool).with(name: "generate_deeplink", arguments: anything).returns({ "content" => [ { "type" => "text", "text" => "javascript:alert(1)/explore" } ] })

        assert HealthCheckService.check!(@row)
        assert_nil Grafana.address(ConnectionSettings.of(@row.reload))
      end

      test "several datasources of a type with none the default are not guessed between, and the one a person chose is read" do
        sources = [ { "uid" => "a", "type" => "loki", "default" => false }, { "uid" => "b", "type" => "loki", "default" => false } ]
        @row.update!(base_config: { "learned" => { "datasources" => sources } })

        assert_nil Grafana.datasource(ConnectionSettings.of(@row), Grafana::LOKI)
        sources.last["default"] = true
        @row.update!(base_config: { "learned" => { "datasources" => sources } })
        assert_equal "b", Grafana.datasource(ConnectionSettings.of(@row), Grafana::LOKI)["uid"]

        @row.store_fields!("logs_datasource" => "a")
        assert_equal "a", Grafana.datasource(ConnectionSettings.of(@row.reload), Grafana::LOKI)["uid"], "the one a person chose wins over the default"
        @row.store_fields!("logs_datasource" => "gone")
        assert_equal "b", Grafana.datasource(ConnectionSettings.of(@row.reload), Grafana::LOKI)["uid"], "a choice Grafana no longer has falls back"
      end

      private

      def tool(name)
        @integration.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: {}, spec: { "tool_name" => name })
      end

      def answer(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
