require "test_helper"

module Integrations
  module Packs
    # The pack takes the site's address as cloudId and answers in the shape Atlassian's MCP server does.
    class JiraTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "jira", name: "Jira issue sync", slug: "jira_issue_sync", settings: {})
        @row = @integration.integration_environments.create!
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer atl_oauth")
        JiraApi.any_instance.stubs(:cloud_id).with("acme.atlassian.net").returns("cloud-1")
        @pack = NativePack.fetch!(@integration)
      end

      def text(result) = result["content"].first["text"]

      test "createjiraissue opens the issue with its description as an Atlassian document, and its key reads as the MCP server's" do
        JiraApi.any_instance.expects(:create_issue).with("cloud-1", has_entries(
          "project" => { "key" => "OPS" }, "issuetype" => { "name" => "Task" }, "summary" => "Rotate", "assignee" => { "accountId" => "acc-1" },
          "description" => { "type" => "doc", "version" => 1, "content" => [
            { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "From INC-1." } ] },
            { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "https://ff.example.com/app/incidents/1",
                                                      "marks" => [ { "type" => "link", "attrs" => { "href" => "https://ff.example.com/app/incidents/1" } } ] } ] }
          ] }
        )).returns("id" => "10001", "key" => "OPS-42")

        result = @pack.createjiraissue(environment_row: @row, arguments: {
          "cloudId" => "acme.atlassian.net", "projectKey" => "OPS", "issueType" => "Task", "summary" => "Rotate", "assignee" => "acc-1",
          "description" => "From INC-1.\n\nhttps://ff.example.com/app/incidents/1"
        })

        assert_equal "OPS-42", text(result)[SourceLinks::Jira::CREATED_KEY, 1]
      end

      test "an issue Jira does not have is an error answer that reads as missing" do
        JiraApi.any_instance.stubs(:issue).raises(JiraApi::Error, "Jira answered 404: Issue does not exist or you do not have permission to see it.")

        result = @pack.getjiraissue(environment_row: @row, arguments: { "cloudId" => "acme.atlassian.net", "issueIdOrKey" => "OPS-404" })

        assert IssueTrackers::Jira.new.missing?(result)
      end

      test "the webhook is registered on the project's issues, lapses in 30 days and is refreshed and removed on the same site" do
        JiraApi.any_instance.expects(:register_webhook).with("cloud-1", "https://ff.example.com/hook", 'project = "OPS"').returns(1000)

        freeze_time do
          webhook = @pack.register_issue_webhook(@row, url: "https://ff.example.com/hook", target: { "site" => "acme.atlassian.net", "project" => "ops" })
          assert_equal [ "1000", nil, 30.days.from_now ], [ webhook.id, webhook.secret, webhook.expires_at ]
        end

        JiraApi.any_instance.expects(:refresh_webhook).with("cloud-1", "1000").returns("2026-11-04T10:00:00.000+0000")
        assert_equal Time.utc(2026, 11, 4, 10), @pack.refresh_issue_webhook(@row, "1000")

        JiraApi.any_instance.expects(:delete_webhook).with("cloud-1", "1000")
        @pack.remove_issue_webhook(@row, "1000")
      end
    end
  end
end
