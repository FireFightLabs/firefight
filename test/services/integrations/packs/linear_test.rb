require "test_helper"

module Integrations
  module Packs
    # The pack answers in the shape Linear's MCP server does, so IssueTrackers::Linear reads it unchanged.
    class LinearTest < ActiveSupport::TestCase
      ISSUE = { "id" => "uuid-1", "identifier" => "ENG-12", "title" => "Rotate", "url" => "https://linear.app/acme/issue/ENG-12/rotate",
                "state" => { "id" => "s-1", "name" => "Todo", "type" => "unstarted" }, "assignee" => { "id" => "u-1", "email" => "alice@example.com" } }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", slug: "linear_issue_sync", settings: {})
        @row = @integration.integration_environments.create!
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer lin_oauth")
        @pack = NativePack.fetch!(@integration)
        @previous_secret = ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"]
        ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = "app-secret"
      end

      teardown { ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = @previous_secret }

      def data(result) = JSON.parse(result["content"].first["text"])

      test "save_issue opens an issue in the team its key names and answers it as the MCP server would" do
        LinearApi.any_instance.stubs(:team).with("ENG").returns("id" => "team-1")
        LinearApi.any_instance.expects(:create_issue).with({ "title" => "Rotate", "teamId" => "team-1", "assigneeId" => "u-1" }).returns(ISSUE)

        answer = data(@pack.save_issue(environment_row: @row, arguments: { "title" => "Rotate", "team" => "ENG", "assignee" => "u-1" }))

        assert_equal({ "id" => "ENG-12", "identifier" => "ENG-12", "title" => "Rotate", "url" => ISSUE["url"], "statusType" => "unstarted",
                       "status" => "Todo", "assignee" => ISSUE["assignee"] }, answer)
        issue = IssueTrackers::Linear.new.send(:issue_of, answer)
        assert_equal [ "ENG-12", Issues::STATE_OPEN, "alice@example.com" ], [ issue.key, issue.state, issue.assignee_email ]
      end

      test "save_issue with an id changes it, and an assignee of null unassigns it" do
        LinearApi.any_instance.expects(:update_issue).with("ENG-12", { "assigneeId" => nil, "stateId" => "s-2" }).returns(ISSUE)

        @pack.save_issue(environment_row: @row, arguments: { "id" => "ENG-12", "assignee" => nil, "state" => "s-2" })
      end

      test "Linear's refusal is the tool's error answer, which reads as a missing issue when it is one" do
        LinearApi.any_instance.stubs(:issue).raises(LinearApi::Error, "Linear refused this: Entity not found: Issue")

        result = @pack.get_issue(environment_row: @row, arguments: { "id" => "ENG-404" })

        assert result["isError"]
        assert IssueTrackers::Linear.new.missing?(result)
      end

      test "the webhook is registered on the team with a secret Firefight makes, and removed by its id" do
        LinearApi.any_instance.stubs(:team).with("ENG").returns("id" => "team-1")
        LinearApi.any_instance.expects(:create_webhook).with do |input|
          input.slice("url", "teamId", "resourceTypes") == { "url" => "https://ff.example.com/hook", "teamId" => "team-1", "resourceTypes" => [ "Issue" ] } &&
            input["secret"].length == 64
        end.returns("id" => "wh-1")

        webhook = @pack.register_issue_webhook(@row, url: "https://ff.example.com/hook", target: { "team" => "ENG" })
        assert_equal "wh-1", webhook.id
        assert_equal 64, webhook.secret.length
        assert_nil webhook.expires_at

        LinearApi.any_instance.expects(:delete_webhook).with("wh-1").returns(true)
        @pack.remove_issue_webhook(@row, "wh-1")
      end

      APP = { "id" => "app-user", "app" => true, "organization" => { "id" => "org-1", "name" => "Acme", "urlKey" => "acme" }, "teams" => [ { "id" => "team-1" } ] }.freeze

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
        assert_equal IntegrationProvider::STATE_NEEDS_ATTENTION, IntegrationProvider.card_for(@workspace, IntegrationProvider.category_for!("Issues"))
                                                                                     .rows.find { |row| row.provider.key == "linear" }.state
      end

      test "a connection made before the app acted as itself keeps working but needs attention, saying to reconnect" do
        LinearApi.any_instance.stubs(:actor).returns(APP.merge("app" => false))

        HealthCheckService.check!(@row)

        assert_equal IntegrationEnvironment::HEALTH_FAILING, @row.reload.health_status
        assert_equal Linear::ACTS_AS_A_PERSON, @row.health_error
        assert_nil @row.installation_id
        assert_equal IntegrationProvider::STATE_NEEDS_ATTENTION, IntegrationProvider.card_for(@workspace, IntegrationProvider.category_for!("Issues"))
                                                                                     .rows.find { |row| row.provider.key == "linear" }.state
      end

      test "the installation reads as removed once Linear no longer takes its token, and as reaching nothing with no team" do
        @row.store_installation!("org-1")
        LinearApi.any_instance.stubs(:actor).raises(LinearApi::Unauthorized, "Linear answered 401: Authentication required")
        assert_equal Installations::REMOVED, Linear.installation(@row).state

        LinearApi.any_instance.stubs(:actor).returns(APP.merge("teams" => []))
        found = Linear.installation(@row)
        assert_equal [ Installations::EMPTIED, "Acme", "https://linear.app/acme/settings/integrations" ], [ found.state, found.account, found.page ]
      end

      test "a connection that acts as the app has its issue changes sent through the app, and one from before still registers its own webhook" do
        assert Issues.registers_webhooks?(@integration)
        assert_not Issues.through_app?(@integration)

        @row.store_installation!("org-1")

        assert_not Issues.registers_webhooks?(@integration)
        assert Issues.through_app?(@integration)
      end

      test "removing the app revokes its token in Linear's documented token field" do
        @row.store_oauth!("access_token" => "lin_app_token", "refresh_token" => "r")
        LinearApi.expects(:revoke).with("lin_app_token").returns(true)

        Linear.uninstall(@row)
      end
    end
  end
end
