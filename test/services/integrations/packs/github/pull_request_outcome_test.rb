require "test_helper"

module Integrations
  module Packs
    class Github
      class PullRequestOutcomeTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "a merged pull request says who merged it, each commit with its author's email, and the conversation" do
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/12", token: "ghs_token").returns("merged_at" => "2026-10-26T10:00:00Z", "merged_by" => { "login" => "ada", "type" => "User" })
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/12/commits?per_page=100", token: "ghs_token").returns([
            { "sha" => "a1", "commit" => { "author" => { "name" => "Halon", "email" => CodeAgentSession::COMMIT_EMAIL }, "message" => "Raise it" }, "parents" => [ {} ] },
            { "sha" => "b1", "author" => { "login" => "ada" }, "commit" => { "author" => { "email" => "ada@acme.test" }, "message" => "Merge main" }, "parents" => [ {}, {} ] }
          ])
          GithubApp.stubs(:get).with("/repos/acme/web/issues/12/comments?per_page=100", token: "ghs_token")
                   .returns([ { "user" => { "login" => "ada", "type" => "User" }, "body" => "Needs a flag" } ])

          outcome = ReviewHost.outcome(@row, repository: "acme/web", number: 12)

          assert ReviewHost.reads_outcomes?(@integration)
          assert_equal [ ReviewHost::STATE_MERGED, "ada", true, nil ], [ outcome.state, outcome.ended_by, outcome.ended_by_person, outcome.reason ]
          assert_equal [ [ "a1", "Halon", CodeAgentSession::COMMIT_EMAIL, false ], [ "b1", "ada", "ada@acme.test", true ] ],
                       outcome.commits.map { |commit| [ commit.sha, commit.author, commit.email, commit.merge ] }
          assert_equal [ [ "ada", true, "Needs a flag" ] ], outcome.comments.map { |comment| [ comment.author, comment.person, comment.body ] }
        end

        test "a closed one says who closed it from its issue, and a bot that did is no person" do
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/12", token: "ghs_token").returns("state" => "closed")
          GithubApp.stubs(:get).with("/repos/acme/web/issues/12", token: "ghs_token").returns("closed_by" => { "login" => "stale[bot]", "type" => "Bot" })
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/12/commits?per_page=100", token: "ghs_token").returns([])
          GithubApp.stubs(:get).with("/repos/acme/web/issues/12/comments?per_page=100", token: "ghs_token").returns([])

          outcome = ReviewHost.outcome(@row, repository: "acme/web", number: 12)

          assert_equal [ ReviewHost::STATE_CLOSED, "stale[bot]", false ], [ outcome.state, outcome.ended_by, outcome.ended_by_person ]
        end

        test "what commits changed is each file's patch from a compare" do
          GithubApp.stubs(:get).with("/repos/acme/web/compare/a1...b1", token: "ghs_token").returns("files" => [ { "filename" => "db/x.rb", "patch" => "@@ -1 +1 @@\n+y" } ])

          assert_equal "diff --git a/db/x.rb b/db/x.rb\n@@ -1 +1 @@\n+y", ReviewHost.changes_between(@row, repository: "acme/web", from: "a1", to: "b1")
        end
      end
    end
  end
end
