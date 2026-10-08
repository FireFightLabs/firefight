require "test_helper"

module Integrations
  module Packs
    class Github
      class BranchesTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("default_branch" => "main")
        end

        test "branches are listed with the default and protected ones marked" do
          GithubApp.expects(:get).with("/repos/acme/web/branches?per_page=20", token: "ghs_token").returns([
            { "name" => "main", "commit" => { "sha" => "a" * 40 }, "protected" => true }, { "name" => "halon/revert", "commit" => { "sha" => "b" * 40 }, "protected" => false }
          ])

          text = text_of(@pack.list_branches(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "  main  #{'a' * 12}  default  protected\n  halon/revert  #{'b' * 12}"
          assert text.end_with?("https://github.com/acme/web/branches")
        end

        test "a branch's protection reads its rulesets and its branch protection, and says when the protection settings cannot be read" do
          GithubApp.stubs(:get).with("/repos/acme/web/branches/main", token: "ghs_token").returns("protected" => true, "commit" => { "sha" => "a" * 40 })
          GithubApp.stubs(:get).with("/repos/acme/web/rules/branches/main?per_page=100", token: "ghs_token").returns([
            { "type" => "deletion" }, { "type" => "pull_request", "parameters" => { "required_approving_review_count" => 2 } },
            { "type" => "required_status_checks", "parameters" => { "required_status_checks" => [ { "context" => "test" } ] } }
          ])
          GithubApp.stubs(:get).with("/repos/acme/web/branches/main/protection", token: "ghs_token").returns(
            "required_pull_request_reviews" => { "required_approving_review_count" => 1, "require_code_owner_reviews" => true },
            "required_status_checks" => { "contexts" => [ "lint" ], "strict" => true }, "enforce_admins" => { "enabled" => false },
            "allow_force_pushes" => { "enabled" => false }, "allow_deletions" => { "enabled" => false }
          )

          text = text_of(@pack.branch_protection(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "main in acme/web is protected, at #{'a' * 12}."
          assert_includes text, "Rulesets say: it cannot be deleted, changes reach it only through a pull request, checks must pass. Required checks: test. Approving reviews needed: 2."
          assert_includes text, "  Reviews: 1 approving, from code owners\n  Checks: lint, and the branch must be up to date\n  Admins may skip these rules"

          GithubApp.stubs(:get).with("/repos/acme/web/branches/main/protection", token: "ghs_token").raises(GithubApp::NotPermitted, "GitHub: Resource not accessible by integration")
          assert_includes text_of(@pack.branch_protection(environment_row: @row, arguments: { "repo" => "acme/web" })),
                          "Branch protection settings not shown: Firefight's GitHub App needs Administration read for them."
        end

        test "a branch is made under halon/ from the default branch" do
          GithubApp.stubs(:get).with("/repos/acme/web/commits/main", token: "ghs_token").returns("sha" => "a" * 40)
          GithubApp.expects(:write).with(:post, "/repos/acme/web/git/refs", { ref: "refs/heads/halon/revert-pool", sha: "a" * 40 }, token: "ghs_token").returns({})

          result = @pack.create_branch(environment_row: @row, arguments: { "repo" => "acme/web", "name" => "revert-pool" })

          assert_includes text_of(result), "Made the branch halon/revert-pool in acme/web from main at #{'a' * 12}."
          assert text_of(result).end_with?("https://github.com/acme/web/tree/halon/revert-pool")
          assert_match "must be a commit SHA, branch or tag", assert_raises(NativePack::Error) {
            @pack.create_branch(environment_row: @row, arguments: { "repo" => "acme/web", "name" => "../main" })
          }.message
        end

        test "only a halon/ branch that is not the default, protected, kept by a rule or still under an open pull request is deleted" do
          GithubApp.expects(:write).never
          assert_equal "Only a branch Firefight made, under halon/, is deleted, and main is not one. A person deletes it on GitHub.",
                       assert_raises(PolicyRefusal) { delete("main") }.message

          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("default_branch" => "halon/main")
          assert_equal "halon/main is the default branch of acme/web, which is never deleted.", assert_raises(PolicyRefusal) { delete("halon/main") }.message
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("default_branch" => "main")

          stub_branch("halon/locked", protected: true)
          assert_equal "halon/locked in acme/web is protected, so it is not deleted.", assert_raises(PolicyRefusal) { delete("halon/locked") }.message

          stub_branch("halon/ruled", rules: [ { "type" => "deletion" } ])
          assert_equal "A ruleset in acme/web keeps halon/ruled from being deleted.", assert_raises(PolicyRefusal) { delete("halon/ruled") }.message

          stub_branch("halon/fix-1", pulls: [ { "number" => 12 } ])
          assert_equal "PR #12 still comes from halon/fix-1, and deleting it would close it. Close it first if that is what is wanted.",
                       assert_raises(PolicyRefusal) { delete("halon/fix-1") }.message
        end

        test "a halon/ branch nothing holds is deleted" do
          stub_branch("halon/fix-2")
          GithubApp.expects(:write).with(:delete, "/repos/acme/web/git/refs/heads/halon/fix-2", token: "ghs_token").returns({})

          assert_includes text_of(delete("halon/fix-2")), "Deleted the branch halon/fix-2 in acme/web."
        end

        private

        def stub_branch(name, protected: false, rules: [], pulls: [])
          GithubApp.stubs(:get).with("/repos/acme/web/branches/#{Http.segment(name)}", token: "ghs_token").returns("protected" => protected, "commit" => { "sha" => "c" * 40 })
          GithubApp.stubs(:get).with("/repos/acme/web/rules/branches/#{Http.segment(name)}?per_page=100", token: "ghs_token").returns(rules)
          GithubApp.stubs(:get).with("/repos/acme/web/pulls?#{{ 'state' => 'open', 'head' => "acme:#{name}", 'per_page' => 10 }.to_query}", token: "ghs_token").returns(pulls)
        end

        def delete(branch) = @pack.delete_branch(environment_row: @row, arguments: { "repo" => "acme/web", "branch" => branch })

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
