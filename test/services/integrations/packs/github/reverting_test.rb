require "test_helper"

module Integrations
  module Packs
    class Github
      class RevertingTest < ActiveSupport::TestCase
        MERGED = "m" * 40
        BEFORE = "p" * 40
        HEAD = "h" * 40
        BRANCH = "halon/revert-pr-412".freeze
        TITLE = "Revert \"Raise the pool size\"".freeze
        MESSAGE = "#{TITLE}\n\nThis reverts PR #412, #{MERGED}.".freeze

        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "a squashed pull request is reverted onto its base as it is now, as one commit, through a new pull request" do
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/412", token: "ghs_token").returns(pull(commits: 3))
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{MERGED}", token: "ghs_token").returns(commit(MERGED, "Raise the pool size (#412)", BEFORE))
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/412/commits?per_page=100", token: "ghs_token")
                   .returns([ { "commit" => { "message" => "one" } }, { "commit" => { "message" => "two" } }, { "commit" => { "message" => "three" } } ])
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{BEFORE}", token: "ghs_token").returns(commit(BEFORE, "Earlier", "e" * 40).merge("tree" => { "sha" => "t" * 40 }))
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{'e' * 40}", token: "ghs_token").returns(commit("e" * 40, "Older", "o" * 40))
          expect_revert(before_tree: "t" * 40)

          text = text_of(@pack.revert_pull_request(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 412, "reason" => "Pool exhaustion" }))

          assert_includes text, "Opened PR #413 #{TITLE} in acme/web, from #{BRANCH} into main, which undoes PR #412 on main as it is now at #{HEAD[0, 12]}."
          assert text.end_with?("https://github.com/acme/web/pull/413")
        end

        test "a rebased pull request is reverted back to before its first commit" do
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/412", token: "ghs_token").returns(pull(commits: 2))
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{MERGED}", token: "ghs_token").returns(commit(MERGED, "two", "f" * 40))
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/412/commits?per_page=100", token: "ghs_token")
                   .returns([ { "commit" => { "message" => "one" } }, { "commit" => { "message" => "two" } } ])
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{'f' * 40}", token: "ghs_token").returns(commit("f" * 40, "one", BEFORE))
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{BEFORE}", token: "ghs_token").returns(commit(BEFORE, "Earlier", "e" * 40).merge("tree" => { "sha" => "t" * 40 }))
          expect_revert(before_tree: "t" * 40)

          assert_includes text_of(@pack.revert_pull_request(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 412 })), "Opened PR #413"
        end

        test "a revert that does not apply cleanly removes its branch and says a person reverts it" do
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/412", token: "ghs_token").returns(pull(commits: 1))
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{MERGED}", token: "ghs_token").returns(commit(MERGED, "Raise", BEFORE, BEFORE.tr("p", "q")))
          GithubApp.stubs(:get).with("/repos/acme/web/git/ref/heads/main", token: "ghs_token").returns("object" => { "sha" => HEAD })
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{BEFORE}", token: "ghs_token").returns("sha" => BEFORE, "tree" => { "sha" => "t" * 40 })
          GithubApp.stubs(:write).with(:post, "/repos/acme/web/git/commits", anything, token: "ghs_token").returns("sha" => "u" * 40)
          GithubApp.stubs(:write).with(:post, "/repos/acme/web/git/refs", anything, token: "ghs_token").returns({})
          GithubApp.stubs(:write).with(:post, "/repos/acme/web/merges", anything, token: "ghs_token").raises(GithubApp::Error, "GitHub answered 409: Merge conflict")
          GithubApp.expects(:write).with(:delete, "/repos/acme/web/git/refs/heads/halon/revert-pr-412", token: "ghs_token").returns({})
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(PolicyRefusal) { @pack.revert_pull_request(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 412 }) }
          assert_match "does not revert cleanly onto the base branch as it is now", error.message
        end

        test "a pull request never merged, or one whose revert branch is already there, is refused" do
          GithubApp.stubs(:get).with("/repos/acme/web/pulls/9", token: "ghs_token").returns(pull(commits: 1).merge("number" => 9, "merged_at" => nil))
          error = assert_raises(PolicyRefusal) { @pack.revert_pull_request(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 9 }) }
          assert_equal "PR #9 in acme/web was never merged, so there is nothing to revert. close_pull_request closes it.", error.message

          GithubApp.stubs(:get).with("/repos/acme/web/pulls/412", token: "ghs_token").returns(pull(commits: 1))
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{MERGED}", token: "ghs_token").returns(commit(MERGED, "Raise", BEFORE))
          GithubApp.stubs(:get).with("/repos/acme/web/git/ref/heads/main", token: "ghs_token").returns("object" => { "sha" => HEAD })
          GithubApp.stubs(:get).with("/repos/acme/web/git/commits/#{BEFORE}", token: "ghs_token").returns("sha" => BEFORE, "tree" => { "sha" => "t" * 40 })
          GithubApp.stubs(:write).with(:post, "/repos/acme/web/git/commits", anything, token: "ghs_token").returns("sha" => "u" * 40)
          GithubApp.stubs(:write).with(:post, "/repos/acme/web/git/refs", anything, token: "ghs_token").raises(GithubApp::Error, "GitHub answered 422: Reference already exists")
          GithubApp.expects(:write).with(:delete, anything, token: "ghs_token").never
          error = assert_raises(PolicyRefusal) { @pack.revert_pull_request(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 412 }) }
          assert_match "#{BRANCH} is already in acme/web", error.message
        end

        test "reverting is a change that needs Contents and Pull requests write" do
          assert_not Github.tool_definitions.find { |tool| tool.name == "revert_pull_request" }.read_only
          assert_equal({ "contents" => Github::WRITE, "pull_requests" => Github::WRITE }, Github::NEEDS.fetch("revert_pull_request"))
        end

        private

        def expect_revert(before_tree:)
          GithubApp.stubs(:get).with("/repos/acme/web/git/ref/heads/main", token: "ghs_token").returns("object" => { "sha" => HEAD })
          GithubApp.expects(:write).with(:post, "/repos/acme/web/git/commits", { message: TITLE, tree: before_tree, parents: [ MERGED ] }, token: "ghs_token").returns("sha" => "u" * 40)
          GithubApp.expects(:write).with(:post, "/repos/acme/web/git/refs", { ref: "refs/heads/#{BRANCH}", sha: HEAD }, token: "ghs_token").returns({})
          GithubApp.expects(:write).with(:post, "/repos/acme/web/merges", { base: BRANCH, head: "u" * 40, commit_message: MESSAGE }, token: "ghs_token")
                   .returns("sha" => "x" * 40, "commit" => { "tree" => { "sha" => "r" * 40 } })
          GithubApp.expects(:write).with(:post, "/repos/acme/web/git/commits", { message: MESSAGE, tree: "r" * 40, parents: [ HEAD ] }, token: "ghs_token").returns("sha" => "v" * 40)
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/git/refs/heads/halon/revert-pr-412", { sha: "v" * 40, force: true }, token: "ghs_token").returns({})
          GithubApp.expects(:open_pull_request).with { |repo, base:, branch:, title:, body:, token:| repo == "acme/web" && base == "main" && branch == BRANCH && title == TITLE && body.start_with?("Reverts #412.") && token == "ghs_token" }
                   .returns("number" => 413, "html_url" => "https://github.com/acme/web/pull/413")
        end

        def pull(commits:)
          { "number" => 412, "title" => "Raise the pool size", "merged_at" => "2026-10-01T10:00:00Z", "merge_commit_sha" => MERGED, "base" => { "ref" => "main" }, "commits" => commits }
        end

        def commit(sha, message, *parents)
          { "sha" => sha, "message" => message, "tree" => { "sha" => "z" * 40 }, "parents" => parents.map { |parent| { "sha" => parent } } }
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
