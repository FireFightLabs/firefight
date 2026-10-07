require "test_helper"

module Integrations
  module Packs
    class Github
      class RepositoryIssuesTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "issues are listed without the pull requests GitHub lists among them, and searched when words are given" do
          GithubApp.expects(:get).with("/repos/acme/web/issues?assignee=ada&direction=desc&labels=bug%2Cincident&per_page=100&sort=updated&state=open", token: "ghs_token")
                   .returns([ issue(5), issue(6).merge("pull_request" => {}) ])

          text = text_of(@pack.list_issues(environment_row: @row, arguments: { "repo" => "acme/web", "labels" => [ "bug", "incident" ], "assignee" => "ada" }))

          assert_includes text, "Issues in acme/web, open:\n  #5 Checkout times out  open  by uros"
          assert_not_includes text, "#6"
          assert text.end_with?("https://github.com/acme/web/issues")

          query = { "order" => "desc", "per_page" => 20, "q" => "repo:acme/web is:issue is:closed timeout", "sort" => "updated" }.to_query
          GithubApp.expects(:get).with("/search/issues?#{query}", token: "ghs_token").returns("items" => [ issue(7) ])
          assert_includes text_of(@pack.list_issues(environment_row: @row, arguments: { "repo" => "acme/web", "state" => "closed", "text" => "timeout" })), "#7 Checkout times out"
        end

        test "an issue is read with its newest comments" do
          GithubApp.stubs(:get).with("/repos/acme/web/issues/5", token: "ghs_token").returns(issue(5).merge("comments" => 2, "body" => "Since 14:00"))
          GithubApp.stubs(:get).with("/repos/acme/web/issues/5/comments?per_page=100&page=1", token: "ghs_token").returns([
            { "user" => { "login" => "ada" }, "created_at" => "t1", "body" => "Seen on EU", "html_url" => "https://github.com/acme/web/issues/5#issuecomment-1" }
          ])

          text = text_of(@pack.issue_lookup(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5 }))

          assert_includes text, "Issue #5: Checkout times out\nState: open"
          assert_includes text, "Labels: bug"
          assert_includes text, "Since 14:00"
          assert_includes text, "Comments, the newest 1 of 2:\n  ada at t1: Seen on EU"
          assert text.end_with?("https://github.com/acme/web/issues/5")
        end

        test "an issue opens with labels the repository has and assignees, and links to its page" do
          GithubApp.stubs(:get).with("/repos/acme/web/labels?per_page=100&page=1", token: "ghs_token").returns([ { "name" => "incident" } ])
          GithubApp.expects(:write).with(:post, "/repos/acme/web/issues", { title: "Bound checkout retries", body: "Seen in INC-4", labels: [ "incident" ], assignees: [ "ada" ] }, token: "ghs_token")
                   .returns(issue(9).merge("title" => "Bound checkout retries"))

          result = @pack.create_issue(environment_row: @row, arguments: { "repo" => "acme/web", "title" => "Bound checkout retries", "body" => "Seen in INC-4",
                                                                           "labels" => [ "incident" ], "assignees" => [ "ada" ] })

          assert_includes text_of(result), "Opened issue #9 Bound checkout retries in acme/web."
          assert text_of(result).end_with?("https://github.com/acme/web/issues/9")
        end

        test "an issue change refuses a pull request, which the pull request tools change" do
          GithubApp.stubs(:get).with("/repos/acme/web/issues/6", token: "ghs_token").returns(issue(6).merge("pull_request" => {}))
          GithubApp.expects(:write).never

          error = assert_raises(NativePack::Error) { @pack.close_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 6 }) }

          assert_equal "#6 in acme/web is a pull request, so the pull request tools change it, such as comment_on_pull_request or close_pull_request.", error.message
        end

        test "comments, edits and labels go on the issue" do
          GithubApp.stubs(:get).with("/repos/acme/web/issues/5", token: "ghs_token").returns(issue(5))
          GithubApp.expects(:write).with(:post, "/repos/acme/web/issues/5/comments", { body: "Mitigated" }, token: "ghs_token").returns("html_url" => "https://github.com/acme/web/issues/5#issuecomment-2")
          assert_includes text_of(@pack.comment_on_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5, "body" => "Mitigated" })), "Commented on issue #5"

          GithubApp.expects(:write).with(:patch, "/repos/acme/web/issues/5", { title: "Checkout times out in EU" }, token: "ghs_token").returns(issue(5).merge("title" => "Checkout times out in EU"))
          assert_includes text_of(@pack.update_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5, "title" => "Checkout times out in EU" })),
                          "Changed its title on issue #5 Checkout times out in EU in acme/web."

          GithubApp.expects(:write).with(:delete, "/repos/acme/web/issues/5/labels/bug", token: "ghs_token").returns([])
          assert_includes text_of(@pack.label_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5, "remove" => "bug" })),
                          "Took bug off issue #5 Checkout times out."
        end

        test "assigning says who GitHub would not assign" do
          GithubApp.stubs(:get).with("/repos/acme/web/issues/5", token: "ghs_token").returns(issue(5))
          GithubApp.expects(:write).with(:post, "/repos/acme/web/issues/5/assignees", { assignees: [ "ada", "bob" ] }, token: "ghs_token")
                   .returns(issue(5).merge("assignees" => [ { "login" => "ada" } ]))

          text = text_of(@pack.assign_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5, "add" => [ "ada", "bob" ] }))

          assert_includes text, "Assigned ada. GitHub did not assign bob, who cannot be assigned in acme/web. Issue #5 Checkout times out is now assigned to ada."
        end

        test "an issue closes with its reason after the comment saying why, and reopens" do
          GithubApp.stubs(:get).with("/repos/acme/web/issues/5", token: "ghs_token").returns(issue(5))
          sequence = sequence("close")
          GithubApp.expects(:write).with(:post, "/repos/acme/web/issues/5/comments", { body: "Not ours" }, token: "ghs_token").in_sequence(sequence).returns({})
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/issues/5", { state: "closed", state_reason: "not_planned" }, token: "ghs_token").in_sequence(sequence).returns({})

          text = text_of(@pack.close_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5, "reason" => "not_planned", "comment" => "Not ours" }))
          assert_includes text, "Closed issue #5 Checkout times out in acme/web as not planned, with a comment saying why. reopen_issue opens it again."

          GithubApp.stubs(:get).with("/repos/acme/web/issues/8", token: "ghs_token").returns(issue(8).merge("state" => "closed"))
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/issues/8", { state: "open", state_reason: "reopened" }, token: "ghs_token").returns({})
          assert_includes text_of(@pack.reopen_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 8 })), "Reopened issue #8"
          assert_equal "Issue #5 in acme/web is already open.", assert_raises(NativePack::Error) { @pack.reopen_issue(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 5 }) }.message
        end

        test "an issue opened or closed is reported so a chat keeps it on its incident" do
          tracker = Integrations::IssueTrackers::Github.new
          opened = Telemetry.result("Opened issue #9 Bound retries in acme/web.", link: Telemetry::Link.new(provider: "GitHub", url: "https://github.com/acme/web/issues/9"))

          report = tracker.report(tool_name: "create_issue", arguments: { "title" => "Bound retries" }, result: opened)

          assert_equal [ Issues::OPENED, "acme/web#9", "Bound retries", "https://github.com/acme/web/issues/9" ], [ report.change, report.key, report.title, report.url ]
          assert tracker.report(tool_name: "close_issue", arguments: {}, result: opened).closed?
          assert_nil tracker.report(tool_name: "comment_on_issue", arguments: {}, result: opened)
          assert Issues.opens?(@integration.tools.new(name: "create_issue"))
          assert_not Issues.syncs?("github"), "GitHub issues are not offered for keeping items in step"
        end

        private

        def issue(number)
          { "number" => number, "title" => "Checkout times out", "state" => "open", "user" => { "login" => "uros" }, "labels" => [ { "name" => "bug" } ],
            "assignees" => [], "created_at" => "t0", "updated_at" => "t1", "comments" => 0, "html_url" => "https://github.com/acme/web/issues/#{number}" }
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
