require "test_helper"

module Integrations
  module Packs
    class GitlabReviewPostingTest < ActiveSupport::TestCase
      PROJECT = "/projects/acme%2Fweb".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
        @row = @integration.integration_environments.create!
        Gitlab.store_credentials!(@row, Gitlab::TOKEN => "glpat-token")
        @pack = Gitlab.new(@integration)
        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/7")
                 .returns("iid" => 7, "title" => "Retries", "state" => "opened", "web_url" => "https://gitlab.com/acme/web/-/merge_requests/7",
                          "diff_refs" => { "base_sha" => "b" * 40, "start_sha" => "s" * 40, "head_sha" => "h" * 40 })
        GitlabApi.any_instance.stubs(:get).with("/user").returns("id" => 42, "username" => "firefight-bot")
      end

      test "a review starts a thread on each line at the merge request's head, then comments its summary" do
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/merge_requests/7/discussions", {
          "body" => "One", "position" => { "position_type" => "text", "base_sha" => "b" * 40, "start_sha" => "s" * 40, "head_sha" => "h" * 40,
                                           "new_path" => "a.rb", "old_path" => "a.rb", "new_line" => 3 }
        }).returns("id" => "6a9c1d3e5f7b", "notes" => [ { "id" => 501 } ])
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/merge_requests/7/notes", { "body" => "Summary" }).returns("id" => 600)

        name, arguments = Gitlab.review_call(PullRequestReviews::REVIEW, repository: "acme/web", number: 7, body: "Summary",
                                                                         comments: [ PullRequestReviews::LineComment.new(path: "a.rb", line: 3, body: "One") ])
        result = @pack.public_send(name, environment_row: @row, arguments: arguments)
        posted = Gitlab.review_posted(PullRequestReviews::REVIEW, result.dig(Telemetry::STRUCTURED, Telemetry::FACTS))

        assert_equal "600", posted.reference
        assert_equal [ "6a9c1d3e5f7b/501" ], posted.comments
        assert_equal [ "https://gitlab.com/acme/web/-/merge_requests/7#note_501" ], posted.urls
        assert_equal "6a9c1d3e5f7b", Gitlab.review_thread_of("6a9c1d3e5f7b/501")
      end

      test "a line GitLab will not place is left without a thread, and the rest still go up" do
        GitlabApi.any_instance.stubs(:post).with("#{PROJECT}/merge_requests/7/discussions", anything).raises(GitlabApi::Error, "GitLab answered 400: line_code can't be blank")
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/merge_requests/7/notes", { "body" => "Summary" }).returns("id" => 600)

        name, arguments = Gitlab.review_call(PullRequestReviews::REVIEW, repository: "acme/web", number: 7, body: "Summary",
                                                                         comments: [ PullRequestReviews::LineComment.new(path: "a.rb", line: 300, body: "One") ])
        result = @pack.public_send(name, environment_row: @row, arguments: arguments)

        assert_includes result["content"].first["text"], "and 1 GitLab would not place on its line"
        assert_equal [ nil ], Gitlab.review_posted(PullRequestReviews::REVIEW, result.dig(Telemetry::STRUCTURED, Telemetry::FACTS)).comments
      end

      test "a line comment's thread is replied to and resolved by its discussion, and its note edited by its own id" do
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/merge_requests/7/discussions/6a9c1d3e5f7b/notes", { "body" => "Fixed in abc1234." }).returns("id" => 502)
        name, arguments = Gitlab.review_call(PullRequestReviews::REPLY, repository: "acme/web", number: 7, reference: "6a9c1d3e5f7b/501", body: "Fixed in abc1234.")
        assert_equal "reply_to_merge_request_thread", name
        assert_equal "6a9c1d3e5f7b/502", @pack.public_send(name, environment_row: @row, arguments: arguments).dig(Telemetry::STRUCTURED, Telemetry::FACTS, "note_id")

        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/7/discussions/6a9c1d3e5f7b")
                 .returns("notes" => [ { "id" => 501, "author" => { "id" => 42, "username" => "firefight-bot" }, "resolved" => false } ])
        GitlabApi.any_instance.expects(:put).with("#{PROJECT}/merge_requests/7/discussions/6a9c1d3e5f7b", { "resolved" => true }).returns({})
        name, arguments = Gitlab.review_call(PullRequestReviews::RESOLVE, repository: "acme/web", number: 7, reference: "6a9c1d3e5f7b/501")
        @pack.public_send(name, environment_row: @row, arguments: arguments)

        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/7/notes/501").returns("id" => 501, "author" => { "id" => 42 })
        GitlabApi.any_instance.expects(:put).with("#{PROJECT}/merge_requests/7/notes/501", { "body" => "Withdrawn." }).returns({})
        name, arguments = Gitlab.review_call(PullRequestReviews::EDIT, repository: "acme/web", number: 7, reference: "6a9c1d3e5f7b/501", body: "Withdrawn.", line: true)
        @pack.public_send(name, environment_row: @row, arguments: arguments)
      end

      test "a note someone else wrote is never edited and their thread never resolved" do
        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/7/notes/77").returns("id" => 77, "author" => { "id" => 9, "username" => "ada" })
        GitlabApi.any_instance.expects(:put).never

        error = assert_raises(PolicyRefusal) do
          @pack.edit_merge_request_comment(environment_row: @row, arguments: { "repo" => "acme/web", "iid" => 7, "note_id" => 77, "body" => "Mine" })
        end
        assert_includes error.message, "comment 77 is ada's"
      end

      test "Firefight is the user the token acts as" do
        identity = @pack.review_identity(@row)

        assert identity.named?([ "firefight-bot", "42" ])
        assert identity.asks?("@firefight-bot review")
      end
    end
  end
end
