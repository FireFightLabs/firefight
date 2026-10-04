require "test_helper"

module Integrations
  module BaselineReaders
    class GrafanaTest < ActiveSupport::TestCase
      NOW = Time.utc(2026, 9, 30, 5)
      WINDOW = (NOW - 7.days)..NOW

      setup do
        @workspace = workspaces(:slack_workspace_one)
        northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
        @northflank_row = northflank.integration_environments.create!
        ResourceMap.record!(@northflank_row, ResourceMap::Snapshot.new(resources: [
          ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web-id", name: "web"),
          ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "odd-id", name: "Odd Name"),
          ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_DATABASE, external_id: "db-id", name: "db")
        ]))
        @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web-id")
        @grafana = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana", slug: "grafana",
                                                   settings: { "server_url" => "https://mcp-grafana.acme.dev/mcp" })
        @row = @grafana.integration_environments.create!(base_config: { "learned" => { "datasources" => [ { "uid" => "prom-uid", "type" => "prometheus", "default" => true } ] } })
        @query = @grafana.tools.create!(name: "query_prometheus", description: "PromQL", read_only: true, enabled: true, params_schema: {},
                                        spec: { "tool_name" => "query_prometheus" })
      end

      test "a week of cpu and memory is read for every container Grafana watches, in one query, and labelled with the connection that read it" do
        body = { "data" => [
          { "metric" => { "container" => "web", "firefight_metric" => "cpu" }, "values" => [ [ NOW.to_i - 900, "0.2" ], [ NOW.to_i, "0.4" ] ] },
          { "metric" => { "container" => "web", "firefight_metric" => "memory" }, "values" => [ [ NOW.to_i, "256" ] ] }
        ] }
        McpClient.any_instance.expects(:call_tool).with do |name:, arguments:|
          name == "query_prometheus" && arguments["datasourceUid"] == "prom-uid" && arguments["stepSeconds"] == 900 &&
            arguments.values_at("startTime", "endTime") == %w[2026-09-23T05:00:00Z 2026-09-30T05:00:00Z] &&
            arguments["expr"] == "label_replace(sum by (container) (rate(container_cpu_usage_seconds_total{container=~\"web\"}[900s])), \"firefight_metric\", \"cpu\", \"\", \"\") or " \
                                 "label_replace(sum by (container) (container_memory_working_set_bytes{container=~\"web\"}) / 1048576, \"firefight_metric\", \"memory\", \"\", \"\")"
        end.returns({ "content" => [ { "type" => "text", "text" => body.to_json } ] })

        assert_equal 2, BaselineSweep.run!(@row, now: NOW)
        baselines = @web.baselines.order(:metric)
        assert_equal [ [ "cpu", "CPU, all pods (Grafana)", "cores", 0.3 ], [ "memory", "Memory, all pods (Grafana)", "MiB", 256.0 ] ],
                     baselines.map { |baseline| [ baseline.metric, baseline.label, baseline.unit, baseline.typical.round(3) ] }
        assert_equal [ @row.id ], baselines.map(&:integration_environment_id).uniq
        logged = Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP)
        assert_equal [ "normal for 1 containers" ], logged.map { |invocation| invocation.params["reads"] }
      end

      test "with query_prometheus off or no Prometheus datasource nothing is read, and a refusal is said on the connection" do
        @query.update!(enabled: false)
        McpClient.any_instance.expects(:call_tool).never
        assert_equal 0, BaselineSweep.run!(@row, now: NOW)

        @query.update!(enabled: true)
        @row.update!(base_config: {})
        assert_equal 0, BaselineSweep.run!(@row, now: NOW)

        @row.update!(base_config: { "learned" => { "datasources" => [ { "uid" => "prom-uid", "type" => "prometheus", "default" => true } ] } })
        McpClient.any_instance.unstub(:call_tool)
        McpClient.any_instance.stubs(:call_tool).returns({ "isError" => true, "content" => [ { "type" => "text", "text" => "execution: query timed out" } ] })
        assert_equal 0, BaselineSweep.run!(@row, now: NOW)
        assert_equal "Grafana could not read normal from Prometheus: execution: query timed out.", @row.reload.baseline_error
      end

      test "a Grafana connection wired to another environment reads nothing for this one" do
        @northflank_row.update!(catalog_entry_id: catalog_entries(:production_env).id)
        @row.update!(catalog_entry_id: catalog_entries(:development_env).id)

        assert_empty Capabilities.watched(@row, Capabilities::METRICS)
        @row.update!(catalog_entry_id: catalog_entries(:production_env).id)
        assert_equal %w[Odd\ Name web], Capabilities.watched(@row, Capabilities::METRICS).map(&:name).sort
        @row.update!(base_config: {})
        assert_empty Capabilities.watched(@row, Capabilities::METRICS), "without a Prometheus datasource it watches nothing"
      end
    end
  end
end
