require "test_helper"

module Integrations
  module Packs
    class NeonTest < ActiveSupport::TestCase
      KEY = "Bearer napi_example".freeze

      setup do
        @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "neon", name: "Neon",
                                                                             settings: { "server_url" => "https://mcp.neon.tech/mcp" })
        @row = @integration.integration_environments.create!
        @pack = Neon.new(@integration)
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
      end

      test "a branch is restored to its own state at a moment, keeping its current state under the name given" do
        NeonApi.any_instance.expects(:branch).with("shop-123", "br-main-1").returns("name" => "main")
        NeonApi.any_instance.expects(:restore_branch).with("shop-123", "br-main-1", { "source_branch_id" => "br-main-1", "source_timestamp" => "2026-10-20T12:30:00Z",
                                                                                      "preserve_under_name" => "main-before-rollback-10201500" }).returns({})

        travel_to Time.utc(2026, 10, 20, 15) do
          text = restore_text({ "source_timestamp" => "2026-10-20T14:30:00+02:00", "preserve_under_name" => "main-before-rollback-10201500" })
          assert_match "Neon restored main to its own state at 2026-10-20T12:30:00Z. Its state before is kept as branch main-before-rollback-10201500", text
          assert_match "open connections dropped", text
        end
      end

      test "a restore needs a zoned moment that has passed or an LSN, and the name its current state is kept under" do
        NeonApi.any_instance.expects(:restore_branch).never

        travel_to Time.utc(2026, 10, 20, 15) do
          assert_match "ISO 8601 time with Z or an offset", restore_refusal("source_timestamp" => "2026-10-20T14:30:00", "preserve_under_name" => "kept")
          assert_match "a moment that has passed", restore_refusal("source_timestamp" => "2026-10-21T00:00:00Z", "preserve_under_name" => "kept")
          assert_match "a Postgres LSN such as 0/1A2B3C4", restore_refusal("source_lsn" => "nope", "preserve_under_name" => "kept")
          assert_match "not both", restore_refusal("source_lsn" => "0/1A2B3C4", "source_timestamp" => "2026-10-20T14:30:00Z", "preserve_under_name" => "kept")
          assert_match "needs a point in its history", restore_refusal("preserve_under_name" => "kept")
          assert_match "Say preserve_under_name", restore_refusal("source_lsn" => "0/1A2B3C4")
          assert_match "project_id is a Neon id", restore_refusal({ "project_id" => "Shop!" }, nil)
        end
      end

      test "a connection Neon's API refuses, as one signed in through its server is, is told to connect again with a key" do
        NeonApi.any_instance.stubs(:branch).raises(NeonApi::Refused, "Neon answered 401: authentication required")

        text = restore_refusal("source_lsn" => "0/1A2B3C4", "preserve_under_name" => "kept")
        assert_match "Neon answered 401: authentication required. Neon refused this connection for its API", text
        assert_match "connect Neon again with an organization API key", text
      end

      test "consumption is read for the project's organization, hourly for a day, one chart per metric" do
        NeonApi.any_instance.expects(:project).with("shop-123").returns("id" => "shop-123", "org_id" => "org-1")
        periods = [ { "period_plan" => "scale", "consumption" => [
          { "timeframe_start" => "2026-10-20T13:00:00Z", "metrics" => [ { "metric_name" => "compute_unit_seconds", "value" => 3600 },
                                                                        { "metric_name" => "public_network_transfer_bytes", "value" => 2048 } ] },
          { "timeframe_start" => "2026-10-20T14:00:00Z", "metrics" => [ { "metric_name" => "compute_unit_seconds", "value" => 7200 } ] }
        ] } ]
        NeonApi.any_instance.expects(:consumption).with(org_id: "org-1", project_id: "shop-123", from: "2026-10-19T15:00:00Z", to: "2026-10-20T15:00:00Z",
                                                        granularity: "hourly", metrics: %w[compute_unit_seconds public_network_transfer_bytes])
               .returns("project_id" => "shop-123", "periods" => periods)

        travel_to Time.utc(2026, 10, 20, 15) do
          result = @pack.call("consumption_history", environment_row: @row, arguments: { "project_id" => "shop-123" })
          text = result["content"].first["text"]
          assert_match "Consumption of project shop-123 on Neon, hourly.", text
          assert_match "compute unit seconds (CU-seconds)", text
          assert_match "max 7200.0 at 2026-10-20T14:00:00Z", text
          charts = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS)
          assert_equal [ "compute unit seconds", "public network transfer bytes" ], charts.map { |chart| chart["title"] }
        end
      end

      test "a metric Neon does not keep is refused, and a plan without consumption history is said" do
        assert_match "Neon keeps no cpu consumption", consumption_refusal("metrics" => [ "cpu" ])

        NeonApi.any_instance.stubs(:project).returns("org_id" => "org-1")
        NeonApi.any_instance.stubs(:consumption).raises(NeonApi::Refused, "Neon answered 403: not available for this account")
        assert_match "only for the Launch, Scale, Agent, Business and Enterprise plans", consumption_refusal({})
      end

      private

      def restore_text(arguments, project = "shop-123")
        text = @pack.call("restore_branch", environment_row: @row, arguments: { "project_id" => project, "branch_id" => "br-main-1" }.compact.merge(arguments))
        text["content"].first["text"]
      end

      def restore_refusal(arguments, project = "shop-123")
        assert_raises(NativePack::Error) { restore_text(arguments, project) }.message
      end

      def consumption_refusal(arguments)
        assert_raises(NativePack::Error) { @pack.call("consumption_history", environment_row: @row, arguments: { "project_id" => "shop-123" }.merge(arguments)) }.message
      end
    end
  end
end
