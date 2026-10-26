require "test_helper"

module Integrations
  module Packs
    class Github
      class ReviewPostingTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
          GithubApp.stubs(:bot_login).returns("firefight-app[bot]")
        end

        test "editing and resolving are changes, and every tool a review posts through is one the pack offers" do
          definitions = Github.tool_definitions.index_by(&:name)

          assert_not definitions.fetch("edit_pull_request_comment").read_only
          assert_not definitions.fetch("resolve_review_thread").read_only
          assert Github::REVIEW_TOOLS.values.all? { |name| definitions.key?(name) }
        end

        test "a comment Firefight wrote is edited, on the conversation or on the code" do
          GithubApp.stubs(:get).with("/repos/acme/checkout/issues/comments/9", token: "ghs_token").returns("user" => { "login" => "firefight-app[bot]" })
          GithubApp.expects(:write).with(:patch, "/repos/acme/checkout/issues/comments/9", { body: "Fixed in abc1234." }, token: "ghs_token")
                   .returns("id" => 9, "html_url" => "https://github.com/acme/checkout/pull/4#issuecomment-9")

          result = @pack.edit_pull_request_comment(environment_row: @row, arguments: { "repo" => "acme/checkout", "comment_id" => 9, "body" => "Fixed in abc1234." })

          assert_includes text_of(result), "Edited comment 9 in acme/checkout."
          assert_equal({ "comment_id" => 9 }, result.dig(Telemetry::STRUCTURED, Telemetry::FACTS))

          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/comments/10", token: "ghs_token").returns("user" => { "login" => "firefight-app[bot]" })
          GithubApp.expects(:write).with(:patch, "/repos/acme/checkout/pulls/comments/10", { body: "Withdrawn." }, token: "ghs_token").returns("id" => 10)
          @pack.edit_pull_request_comment(environment_row: @row, arguments: { "repo" => "acme/checkout", "comment_id" => 10, "body" => "Withdrawn.", "review" => true })
        end

        test "a comment someone else wrote is never edited" do
          GithubApp.stubs(:get).with("/repos/acme/checkout/issues/comments/9", token: "ghs_token").returns("user" => { "login" => "ada" })
          GithubApp.expects(:write).never

          error = assert_raises(PolicyRefusal) do
            @pack.edit_pull_request_comment(environment_row: @row, arguments: { "repo" => "acme/checkout", "comment_id" => 9, "body" => "Mine now" })
          end
          assert_includes error.message, "comment 9 is ada's"
        end

        test "a thread Firefight started is resolved by the comment that started it, and anyone else's is refused" do
          threads = { "repository" => { "pullRequest" => { "reviewThreads" => { "pageInfo" => { "hasNextPage" => false }, "nodes" => [
            { "id" => "T_1", "isResolved" => false, "comments" => { "nodes" => [ { "fullDatabaseId" => 31, "viewerDidAuthor" => true } ] } },
            { "id" => "T_2", "isResolved" => false, "comments" => { "nodes" => [ { "fullDatabaseId" => 32, "viewerDidAuthor" => false } ] } }
          ] } } } }
          GithubApp.stubs(:graphql).with(ReviewPosting::THREADS_QUERY, anything, token: "ghs_token").returns(threads)
          GithubApp.expects(:graphql).with(ReviewPosting::RESOLVE_MUTATION, { id: "T_1" }, token: "ghs_token")
                   .returns("resolveReviewThread" => { "thread" => { "id" => "T_1", "isResolved" => true } })

          result = @pack.resolve_review_thread(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 4, "comment_id" => 31 })
          assert_includes text_of(result), "Resolved the review thread comment 31 started on PR #4 in acme/checkout."

          assert_raises(PolicyRefusal) { @pack.resolve_review_thread(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 4, "comment_id" => 32 }) }
          assert_raises(NativePack::Error) { @pack.resolve_review_thread(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 4, "comment_id" => 99 }) }
        end

        test "a review is pinned to the commit asked and answers each line comment's id in order" do
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/4", token: "ghs_token")
                   .returns("number" => 4, "title" => "Retries", "state" => "open", "head" => { "sha" => "f" * 40 }, "html_url" => "https://github.com/acme/checkout/pull/4")
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/pulls/4/reviews",
                                         { commit_id: "abc1234", event: "COMMENT", body: "Two problems.",
                                           comments: [ { path: "a.rb", line: 3, side: "RIGHT", body: "One" }, { path: "b.rb", line: 8, side: "RIGHT", body: "Two" } ] },
                                         token: "ghs_token")
                   .returns("id" => 55, "html_url" => "https://github.com/acme/checkout/pull/4#pullrequestreview-55")
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/4/reviews/55/comments?per_page=100", token: "ghs_token")
                   .returns([ { "id" => 702, "path" => "b.rb", "line" => 8, "body" => "Two" }, { "id" => 701, "path" => "a.rb", "line" => 3, "body" => "One" } ])

          name, arguments = Github.review_call(PullRequestReviews::REVIEW, repository: "acme/checkout", number: 4, body: "Two problems.", commit: "abc1234",
                                                                           comments: [ PullRequestReviews::LineComment.new(path: "a.rb", line: 3, body: "One"),
                                                                                       PullRequestReviews::LineComment.new(path: "b.rb", line: 8, body: "Two") ])
          result = @pack.public_send(name, environment_row: @row, arguments: arguments)
          posted = Github.review_posted(PullRequestReviews::REVIEW, result.dig(Telemetry::STRUCTURED, Telemetry::FACTS))

          assert_equal "55", posted.reference
          assert_equal %w[701 702], posted.comments
        end

        test "Firefight is known by its App's bot and its slug" do
          identity = @pack.review_identity(@row)

          assert identity.named?([ "firefight-app[bot]" ])
          assert identity.asks?("@firefight-app review please")
          assert identity.asks?("Could @halon review this?")
          assert_not identity.asks?("@firefight-app what does this do?")
          assert_not identity.asks?("please review")
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
