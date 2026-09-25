require "test_helper"

module Integrations
  module Packs
    class NorthflankTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
        @row = @integration.integration_environments.create!
        Northflank.store_credentials!(@row, Northflank::API_TOKEN => " nf-token ", Northflank::PROJECT => "firefight")
        @pack = Northflank.new(@integration)
        NorthflankApi.any_instance.stubs(:services).returns([
          { "id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/firefight-labs/firefight/web",
            "status" => { "deployment" => { "status" => "COMPLETED" } } }
        ])
        NorthflankApi.any_instance.stubs(:addons).returns([
          { "id" => "db", "name" => "db", "spec" => { "type" => "postgresql" }, "status" => "running", "appId" => "/firefight-labs/firefight/db" }
        ])
      end

      test "the token and project are stored trimmed, and every tool only reads" do
        assert_equal "nf-token", @row.reload.credentials_hash[Northflank::API_TOKEN]
        assert Northflank.tool_definitions.all?(&:read_only)
      end

      test "a token or project Northflank refuses is said before anything is saved" do
        NorthflankApi.any_instance.stubs(:project).raises(NorthflankApi::Error, "Northflank answered 401: Unauthorized")

        refusal = Northflank.credential_refusal(Northflank::API_TOKEN => "wrong", Northflank::PROJECT => "firefight")

        assert_match "Northflank refused this token or project", refusal
        assert_match "401", refusal
        assert_equal "Paste an API token.", Northflank.credential_refusal(Northflank::PROJECT => "firefight")
      end

      test "the project's services and databases are listed with their state" do
        text = call(:list_resources)

        assert_match "web (web), combined service, completed", text
        assert_match "db (db), postgresql database, running", text
      end

      test "logs are searched on the named resource, newest first, with the filters it was given" do
        NorthflankApi.any_instance.expects(:logs).with do |project, kind, id, query|
          project == "firefight" && kind == Northflank::KIND_SERVICES && id == "web" &&
            query["textIncludes"] == "timeout" && query["direction"] == "backward" && query["type"] == "runtime"
        end.returns([ { "ts" => "2026-09-25T14:02:03Z", "containerId" => "web-1", "log" => "upstream timeout after 30s" } ])

        text = call(:search_logs, "resource" => "WEB", "text" => "timeout", "minutes" => 30)

        assert_match "2026-09-25T14:02:03Z web-1 upstream timeout after 30s", text
      end

      test "metrics come back as numbers for the model and as charts for the person, with a link to the live page" do
        NorthflankApi.any_instance.stubs(:metrics).returns(
          "http5xxResponses" => {
            "metricInfo" => { "metricUnit" => "count" },
            "values" => [ { "metadata" => { "containerId" => "web-1" },
                            "data" => [ { "ts" => "2026-09-25T14:00:00Z", "value" => 0 }, { "ts" => "2026-09-25T14:05:00Z", "value" => 42 } ] } ]
          }
        )

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => [ "http5xxResponses" ] })

        text = result["content"].sole["text"]
        assert_match "5xx responses of web (count)", text
        assert_match "web-1: min 0.0, avg 21.0, max 42.0 at 2026-09-25T14:05:00Z", text
        chart = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).sole
        assert_equal [ [ "2026-09-25T14:00:00Z", 0.0 ], [ "2026-09-25T14:05:00Z", 42.0 ] ], chart["series"].sole["points"]
        assert_equal "https://app.northflank.com/t/firefight-labs/project/firefight/services/web", chart["link"]
      end

      test "a metric with more containers than a chart keeps says how many were left out" do
        containers = (1..10).map { |index| { "metadata" => { "containerId" => "web-#{index}" }, "data" => [ { "ts" => "2026-09-25T14:00:00Z", "value" => index } ] } }
        NorthflankApi.any_instance.stubs(:metrics).returns("cpu" => { "metricInfo" => { "metricUnit" => "vCPU" }, "values" => containers })

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => [ "cpu" ] })

        assert_match "2 more series not shown, only the first 8 are kept", result["content"].sole["text"]
        assert_match "2 more series not shown", result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).sole["summary"]
      end

      test "a resource that is not in the project says what to do instead" do
        error = assert_raises(NativePack::Error) { call(:search_logs, "resource" => "checkout") }

        assert_match "list_resources shows what there is", error.message
      end

      test "only services have builds" do
        error = assert_raises(NativePack::Error) { call(:recent_builds, "resource" => "db") }

        assert_match "only services have builds", error.message
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
