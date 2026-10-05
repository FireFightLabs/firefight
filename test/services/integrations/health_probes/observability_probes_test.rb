require "test_helper"

module Integrations
  module HealthProbes
    class ObservabilityProbesTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
      end

      test "OpenStatus answers every page of monitors with the address each checks" do
        pages = { 1 => { "items" => [ { "id" => 1, "name" => "Shop", "url" => "https://shop.acme.com", "active" => true } ], "pagination" => { "totalPages" => 2 } },
                  2 => { "items" => [ { "id" => 2, "name" => "Docs", "url" => "https://docs.acme.com" } ], "pagination" => { "totalPages" => 2 } } }
        asked = []
        learned = Openstatus.new(settings_for("openstatus")) { |name, arguments, _reads| asked << [ name, arguments ] && answer(pages.fetch(arguments["page"])) }.check!

        assert_equal [ [ "list_monitors", { "page" => 1, "perPage" => 50 } ], [ "list_monitors", { "page" => 2, "perPage" => 50 } ] ], asked
        assert_equal [ 1, 2 ], learned["monitors"].map { |monitor| monitor["id"] }
      end

      test "a refusal is raised with the provider's words, and a tool that is off teaches nothing" do
        settings = settings_for("openstatus")
        error = assert_raises(RemoteReader::Refused) do
          Openstatus.new(settings) { { "isError" => true, "content" => [ { "type" => "text", "text" => "Invalid API key" } ] } }.check!
        end
        assert_equal "OpenStatus refused list_monitors: Invalid API key.", error.message
        assert_nil Openstatus.new(settings) { nil }.check!
      end

      test "Honeybadger answers projects and their uptime sites, never a project's API key" do
        projects = { "results" => [ { "id" => 11, "name" => "Web", "token" => "hbp_secret" } ], "links" => {} }
        project = { "id" => 11, "token" => "hbp_secret", "sites" => [ { "id" => "s1", "name" => "Shop", "url" => "https://shop.acme.com", "state" => "up" } ] }
        learned = Honeybadger.new(settings_for("honeybadger")) { |name, _arguments, _reads| answer(name == "list_projects" ? projects : project) }.check!

        assert_equal({ "projects" => [ { "id" => 11, "name" => "Web", "sites" => [ { "id" => "s1", "name" => "Shop", "url" => "https://shop.acme.com" } ] } ] }, learned)
        assert_not_includes learned.to_json, "hbp_secret"
      end

      test "Better Stack answers monitors from an answer in the Uptime API's shape and keeps what it knew for any other" do
        monitors = { "data" => [ { "id" => "175", "attributes" => { "url" => "https://shop.acme.com", "pronounceable_name" => "Shop" } } ] }
        settings = settings_for("betterstack")

        assert_equal({ "monitors" => [ { "id" => "175", "name" => "Shop", "url" => "https://shop.acme.com" } ] }, Betterstack.new(settings) { answer(monitors) }.check!)
        assert_nil Betterstack.new(settings) { answer("Shop is up") }.check!
      end

      test "Logfire keeps the project's own address, only on the app of the connection's region" do
        eu = settings_for("logfire", region: "eu")

        assert_equal({ "project_url" => "https://logfire-eu.pydantic.dev/acme/web" },
                     Logfire.new(eu) { answer("https://logfire-eu.pydantic.dev/acme/web?q=level%3D%27error%27") }.check!)
        assert_raises(RemoteReader::Refused) { Logfire.new(eu) { answer("https://logfire-us.pydantic.dev/acme/web") }.check! }
      end

      test "SigNoz keeps its team's address from a service's page" do
        body = { "data" => [ { "serviceName" => "web", "webUrl" => "https://acme.us.signoz.cloud/services/web" } ], "pagination" => {} }

        assert_equal({ "address" => "https://acme.us.signoz.cloud" }, Signoz.new(settings_for("signoz")) { answer(body) }.check!)
      end

      test "Honeycomb and Axiom fail a connection whose environment or datasets the provider does not list" do
        honeycomb = settings_for("honeycomb", fields: { "environment_slug" => "production" })
        assert_nil Honeycomb.new(honeycomb) { answer("Team acme. Environments: production (4 datasets), staging (2 datasets)") }.check!
        error = assert_raises(RemoteReader::Refused) { Honeycomb.new(honeycomb) { answer("Team acme. Environments: production-eu (4 datasets)") }.check! }
        assert_match "does not list an environment called production", error.message

        axiom = settings_for("axiom", fields: { "logs_dataset" => "logs", "traces_dataset" => "otel-traces" })
        assert_nil Axiom.new(axiom) { answer("name,description\nlogs,App logs\notel-traces,Traces") }.check!
        error = assert_raises(RemoteReader::Refused) { Axiom.new(axiom) { answer("name\nlogs-old") }.check! }
        assert_equal "Axiom does not list logs and otel-traces among this organization's datasets. Connect again with the names Axiom shows.", error.message
      end

      test "the executor checks a provider with a probe through its switched on tools, keeps what it learned and records the call" do
        settings_for("openstatus")
        row = @row
        row.integration.tools.create!(name: "list_monitors", description: "Monitors", read_only: true, enabled: true, params_schema: {}, spec: { "tool_name" => "list_monitors" })
        McpClient.any_instance.stubs(:ping).returns(true)
        McpClient.any_instance.stubs(:call_tool).returns(answer({ "items" => [ { "id" => 4, "name" => "API", "url" => "https://api.acme.com" } ], "pagination" => { "totalPages" => 1 } }))

        assert HealthCheckService.check!(row)
        assert_equal [ 4 ], Openstatus.monitors(ConnectionSettings.of(row.reload)).map { |monitor| monitor["id"] }
        invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "openstatus.list_monitors")
        assert_equal [ AbilityGateway::SOURCE_HEALTH_CHECK, Ability::Invocation::OUTCOME_SUCCESS ], [ invocation.source, invocation.outcome ]
      end

      private

      def settings_for(provider, region: nil, fields: {})
        entry = IntegrationProvider.find(provider)
        integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: provider, slug: provider,
                                                      settings: { "server_url" => entry.region(region)&.server_url || entry.server_url,
                                                                  Integration::REGION_SETTING => region }.compact)
        @row = integration.integration_environments.create!(base_config: { IntegrationEnvironment::FIELDS_KEY => fields })
        ConnectionSettings.of(@row)
      end

      def answer(body) = { "content" => [ { "type" => "text", "text" => body.is_a?(String) ? body : body.to_json } ] }
    end
  end
end
