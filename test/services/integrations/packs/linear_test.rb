require "test_helper"

module Integrations
  module Packs
    # What Firefight's Linear app adds to the MCP connection it makes: its check as the app, its installation, and its
    # issue changes arriving through the app.
    class LinearTest < ActiveSupport::TestCase
      APP = { "id" => "app-user", "app" => true, "organization" => { "id" => "org-1", "name" => "Acme", "urlKey" => "acme" }, "teams" => [ { "id" => "team-1" } ] }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
                                                       settings: { "server_url" => "https://mcp.linear.app/mcp", Integration::APP_SETTING => true })
        @row = @integration.integration_environments.create!
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer lin_oauth")
        McpClient.stubs(:new).returns(stub(ping: true))
        @previous_secret = ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"]
        ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = "app-secret"
      end

      teardown { ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = @previous_secret }

      def linear_card = IntegrationProvider.card_for(@workspace, IntegrationProvider.category_for!("Issues")).rows.find { |row| row.provider.key == "linear" }

      test "a token that acts as the app keeps its organization as the connection's installation" do
        LinearApi.any_instance.stubs(:actor).returns(APP)

        HealthCheckService.check!(@row)

        assert_equal [ "org-1", IntegrationEnvironment::HEALTH_HEALTHY ], [ @row.reload.installation_id, @row.health_status ]
        assert Installations.installed?(@row)
      end

      test "without the app's webhook signing secret set on the deployment, an app connection needs attention and says why" do
        ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = nil
        LinearApi.any_instance.stubs(:actor).returns(APP)

        HealthCheckService.check!(@row)

        assert_equal [ IntegrationEnvironment::HEALTH_FAILING, Linear::APP_WEBHOOK_UNSET ], [ @row.reload.health_status, @row.health_error ]
        assert_equal "org-1", @row.installation_id
        assert_equal IntegrationProvider::STATE_NEEDS_ATTENTION, linear_card.state
      end

      test "an app token that acts as a person needs attention, saying to reconnect" do
        LinearApi.any_instance.stubs(:actor).returns(APP.merge("app" => false))

        HealthCheckService.check!(@row)

        assert_equal [ IntegrationEnvironment::HEALTH_FAILING, Linear::ACTS_AS_A_PERSON ], [ @row.reload.health_status, @row.health_error ]
        assert_nil @row.installation_id
        assert_equal IntegrationProvider::STATE_NEEDS_ATTENTION, linear_card.state
      end

      test "a connection signed in to the MCP server or made with a token is checked as the server alone" do
        @integration.update!(settings: { "server_url" => "https://mcp.linear.app/mcp" })
        LinearApi.any_instance.expects(:actor).never

        HealthCheckService.check!(@row)

        assert_equal IntegrationEnvironment::HEALTH_HEALTHY, @row.reload.health_status
        assert_nil @row.installation_id
      end

      test "the installation reads as removed once Linear no longer takes its token, and as reaching nothing with no team" do
        @row.store_installation!("org-1")
        LinearApi.any_instance.stubs(:actor).raises(LinearApi::Unauthorized, "Linear answered 401: Authentication required")
        assert_equal Installations::REMOVED, Linear.installation(@row).state

        LinearApi.any_instance.stubs(:actor).returns(APP.merge("teams" => []))
        found = Linear.installation(@row)
        assert_equal [ Installations::EMPTIED, "Acme", "https://linear.app/acme/settings/integrations" ], [ found.state, found.account, found.page ]
      end

      test "a connection that acts as the app has its issue changes sent through the app and registers no webhook" do
        assert_not Issues.through_app?(@integration)

        @row.store_installation!("org-1")

        assert Issues.through_app?(@integration)
        assert_not Issues.registers_webhooks?(@integration)
      end

      test "a tool on a connection whose app was removed answers why rather than calling Linear's server" do
        @row.store_installation!("org-1")
        @row.installation_marked!(Installations::REMOVED)
        tool = @integration.tools.create!(name: "get_issue", description: "d", read_only: true, enabled: true, params_schema: {})
        McpClient.expects(:new).never

        result = McpExecutor.call(tool: tool, environment_row: @row, arguments: { "id" => "ENG-1" })

        assert result["isError"]
        assert_match "Firefight's app was removed from", result["content"].first["text"]
      end

      test "removing the app revokes its token in Linear's documented token field" do
        @row.store_oauth!("access_token" => "lin_app_token", "refresh_token" => "r")
        LinearApi.expects(:revoke).with("lin_app_token").returns(true)

        Linear.uninstall(@row)
      end

      test "the pack offers no tools of its own, so every tool is Linear's server's" do
        assert_empty Linear.tool_definitions
      end
    end
  end
end
