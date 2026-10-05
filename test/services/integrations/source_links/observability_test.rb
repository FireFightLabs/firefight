require "test_helper"

module Integrations
  module SourceLinks
    class ObservabilityTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
      end

      test "a Logfire query links to the live view of the project its probe read, filtered to the service, over the same time" do
        builder = Logfire.new(settings_for("logfire", region: "eu", learned: { "project_url" => "https://logfire-eu.pydantic.dev/acme/web" }))
        link = builder.link(tool_name: "query_run", arguments: {
          "query" => "SELECT message FROM records WHERE service_name = 'web' LIMIT 5", "min_timestamp" => "2026-10-04T09:00:00Z", "max_timestamp" => "2026-10-04T10:00:00Z"
        })

        assert_equal "https://logfire-eu.pydantic.dev/acme/web?q=service_name+%3D+%27web%27&since=2026-10-04T09%3A00%3A00Z&until=2026-10-04T10%3A00%3A00Z", link.url
        assert_nil builder.link(tool_name: "dashboard_list", arguments: {})
        assert_nil Logfire.new(settings_for("logfire", slug: "logfire_two")).link(tool_name: "query_run", arguments: {})
        moved = settings_for("logfire", slug: "logfire_three", region: "us", learned: { "project_url" => "https://logfire-eu.pydantic.dev/acme/web" })
        assert_nil Logfire.new(moved).link(tool_name: "query_run", arguments: {})
      end

      test "a SigNoz count links to the service's page on the team's own address, and a log search to nothing" do
        builder = Signoz.new(settings_for("signoz", region: "eu", learned: { "address" => "https://acme.eu.signoz.cloud" }))

        assert_equal "https://acme.eu.signoz.cloud/services/web%20api", builder.link(tool_name: "signoz_aggregate_traces", arguments: { "service" => "web api" }).url
        assert_nil builder.link(tool_name: "signoz_search_logs", arguments: { "service" => "web" })
      end

      test "a call about one OpenStatus monitor links to its page" do
        builder = Openstatus.new(settings_for("openstatus"))

        assert_equal "https://app.openstatus.dev/monitors/42", builder.link(tool_name: "get_monitor_status", arguments: { "monitorId" => 42 }).url
        assert_nil builder.link(tool_name: "list_monitors", arguments: {})
      end

      test "an Axiom query links to its query page in the organization, with the same APL and time" do
        builder = Axiom.new(settings_for("axiom", fields: { "org_id" => "acme-x1" }))
        travel_to Time.utc(2026, 10, 4, 10) do
          link = builder.link(tool_name: "querydataset", arguments: { "apl" => "['logs'] | take 5", "startTime" => "now-30m", "endTime" => "now" })
          form = JSON.parse(Rack::Utils.parse_query(URI.parse(link.url).query)["initForm"])

          assert_equal "https://app.axiom.co/acme-x1/query", link.url.split("?").first
          assert_equal({ "apl" => "['logs'] | take 5", "queryOptions" => { "startTime" => "2026-10-04T09:30:00Z", "endTime" => "2026-10-04T10:00:00Z" } }, form)
        end
        assert_nil Axiom.new(settings_for("axiom", slug: "axiom_two")).link(tool_name: "querydataset", arguments: { "apl" => "x" })
      end

      test "the executor removes a Honeybadger project's API key before anyone reads it" do
        settings_for("honeybadger")
        tool = @row.integration.tools.create!(name: "list_projects", description: "Projects", params_schema: {}, spec: { "tool_name" => "list_projects" })
        McpClient.any_instance.stubs(:call_tool).returns({ "content" => [ { "type" => "text", "text" => { "results" => [ { "id" => 1, "name" => "Web", "token" => "hbp_secret" } ] }.to_json } ] })

        text = McpExecutor.call(tool: tool, environment_row: @row, arguments: {})["content"].first["text"]
        assert_not_includes text, "hbp_secret"
        assert_equal Redactions::REMOVED, JSON.parse(text).dig("results", 0, "token")
      end

      private

      def settings_for(provider, slug: provider, region: nil, fields: {}, learned: {})
        entry = IntegrationProvider.find(provider)
        integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: slug, slug: slug,
                                                      settings: { "server_url" => entry.region(region)&.server_url || entry.server_url,
                                                                  Integration::REGION_SETTING => region }.compact)
        @row = integration.integration_environments.create!(base_config: { IntegrationEnvironment::FIELDS_KEY => fields, IntegrationEnvironment::LEARNED_KEY => learned })
        ConnectionSettings.of(@row)
      end
    end
  end
end
