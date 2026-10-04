require "test_helper"

module Integrations
  module BaselineReaders
    class NewrelicTest < ActiveSupport::TestCase
      NOW = Time.utc(2026, 9, 30, 5)

      setup do
        @workspace = workspaces(:slack_workspace_one)
        northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
        @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
        @newrelic = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "newrelic", name: "New Relic", slug: "newrelic",
                                                    settings: { "server_url" => "https://mcp.newrelic.com/mcp/", "region" => "us" })
        @row = @newrelic.integration_environments.create!
        @row.store_fields!("account_id" => "1234567")
        @nrql = @newrelic.tools.create!(name: "execute_nrql_query", description: "NRQL", read_only: true, enabled: true,
                                        params_schema: { "type" => "object", "properties" => { "account_id" => { "type" => "integer" }, "query" => {} } })
        @web = resource("web", ResourceMap::KIND_SERVICE)
        resource("main-db", ResourceMap::KIND_DATABASE)
      end

      test "each service New Relic watches gets throughput, error rate and response time from one query, kept beside the platform's own" do
        ResourceMap::Baseline.record!(@northflank_row, [ @web ], [ ResourceMap::Baseline::Found.new(key: @web.key, metric: "cpu", label: "CPU", unit: "vCPU", points: [ [ NOW, 0.2 ] ]) ],
                                      window_from: NOW - 7.days, window_to: NOW)
        asked = []
        McpClient.any_instance.stubs(:call_tool).with { |name:, arguments:| asked << [ name, arguments ] }.returns(answer(
          { "beginTimeSeconds" => NOW.to_i - 7200, "transactions" => 120, "throughput" => 2.0, "error_rate" => 1.5, "response_time" => 180.0 },
          { "beginTimeSeconds" => NOW.to_i - 3600, "transactions" => 0, "throughput" => 0.0, "error_rate" => 0.0, "response_time" => nil }
        ))

        assert_equal 3, BaselineSweep.run!(@row, now: NOW)

        assert_equal [ [ "execute_nrql_query", 1_234_567 ] ], asked.map { |name, arguments| [ name, arguments["account_id"] ] }
        assert_match "FROM Transaction WHERE appName = 'web' SINCE '2026-09-23T05:00:00Z' UNTIL '2026-09-30T05:00:00Z' TIMESERIES 1 hour", asked.sole.last["query"]
        newrelic = @web.baselines.reload.where(integration_environment: @row).index_by(&:metric)
        assert_equal %w[error_rate response_time throughput], newrelic.keys.sort
        assert_equal [ "cpu" ], @web.baselines.where(integration_environment: @northflank_row).map(&:metric)
        assert_equal [ 2, 1 ], [ newrelic["throughput"].points, newrelic["error_rate"].points ]
        assert_equal [ "Response time (New Relic)", "ms", 180.0 ], newrelic["response_time"].then { |baseline| [ baseline.label, baseline.unit, baseline.peak ] }
        assert Ability::Invocation.exists?(action_key: "newrelic.execute_nrql_query")
      end

      test "a service New Relic never saw keeps no baselines from it, and an answer it cannot read is said on the connection" do
        McpClient.any_instance.stubs(:call_tool).returns(answer({ "beginTimeSeconds" => NOW.to_i, "transactions" => 0, "throughput" => 0.0 }))
        assert_equal 0, BaselineSweep.run!(@row, now: NOW)
        assert_nil @row.reload.baseline_error

        McpClient.any_instance.stubs(:call_tool).returns({ "content" => [ { "type" => "text", "text" => "done" } ] })
        BaselineSweep.run!(@row, now: NOW)
        assert_match "without the results list", @row.reload.baseline_error
      end

      test "without an account the connection says why, and with its query tool off nothing is read" do
        McpClient.any_instance.expects(:call_tool).never
        @row.store_fields!({})
        BaselineSweep.run!(@row, now: NOW)
        assert_match "give its account ID", @row.reload.baseline_error

        @row.store_fields!("account_id" => "1234567")
        @nrql.update!(enabled: false)
        assert_equal 0, BaselineSweep.run!(@row.reload, now: NOW)
      end

      private

      def resource(name, kind)
        ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: kind, external_id: "#{name}-id",
                                      name: name, integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
      end

      def answer(*rows) = { "content" => [ { "type" => "text", "text" => { "results" => rows }.to_json } ] }
    end
  end
end
