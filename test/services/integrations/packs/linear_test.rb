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
      end

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
    end
  end
end
