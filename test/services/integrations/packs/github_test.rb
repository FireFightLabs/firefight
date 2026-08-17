require "test_helper"

module Integrations
  module Packs
    class GithubTest < ActiveSupport::TestCase
      fixtures :workspaces, :users, :workspace_memberships

      setup do
        @integration = Integration.create!(
          workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
          provider: "github", name: "GitHub"
        )
        @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
        @pack = Github.new(@integration)
        GithubApp.stubs(:installation_token).returns("ghs_token")
      end

      test "pr_lookup renders the PR with its changed files" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412", token: "ghs_token").returns(
          "number" => 412, "title" => "Fix payment retries", "state" => "closed",
          "merged_at" => "2026-08-01T10:00:00Z", "user" => { "login" => "uros" },
          "head" => { "ref" => "fix-retries" }, "base" => { "ref" => "main" },
          "changed_files" => 2, "additions" => 10, "deletions" => 3, "body" => "Retries were unbounded."
        )
        GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/files?per_page=30", token: "ghs_token").returns([
          { "filename" => "app/models/payment.rb", "additions" => 8, "deletions" => 2 },
          { "filename" => "test/models/payment_test.rb", "additions" => 2, "deletions" => 1 }
        ])

        text = @pack.pr_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 })

        assert_includes text, "PR #412: Fix payment retries"
        assert_includes text, "merged at 2026-08-01T10:00:00Z"
        assert_includes text, "app/models/payment.rb (+8 -2)"
        assert_includes text, "Retries were unbounded."
      end

      test "commit_lookup renders the commit with stats and files" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/commits/abc123", token: "ghs_token").returns(
          "sha" => "abc123", "stats" => { "additions" => 5, "deletions" => 1 },
          "commit" => { "message" => "Tighten retry budget",
                        "author" => { "name" => "Uros", "date" => "2026-08-01T09:00:00Z" } },
          "files" => [ { "filename" => "app/models/payment.rb", "additions" => 5, "deletions" => 1 } ]
        )

        text = @pack.commit_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "sha" => "abc123" })

        assert_includes text, "Commit abc123"
        assert_includes text, "Tighten retry budget"
        assert_includes text, "app/models/payment.rb (+5 -1)"
      end

      test "repo arguments must be owner/name shaped" do
        error = assert_raises(NativePack::Error) do
          @pack.pr_lookup(environment_row: @row, arguments: { "repo" => "../../etc", "number" => 1 })
        end
        assert_match(/owner\/name/, error.message)
      end

      test "pr numbers must be integers and shas must be hex" do
        assert_raises(NativePack::Error) do
          @pack.pr_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => "latest" })
        end
        assert_raises(NativePack::Error) do
          @pack.commit_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "sha" => "not-a-sha" })
        end
      end

      test "health check proves an installation token can be minted" do
        GithubApp.expects(:installation_token).with(@row).returns("ghs_token")
        @pack.check_health!(@row)
      end

      test "the registry resolves github to this pack" do
        assert_equal Github, NativePack.for("github")
      end

      test "fetch_file returns a numbered slice with context around the requested lines" do
        with_fixture_clone do
          text = @pack.fetch_file(environment_row: @row,
                                  arguments: { "repo" => "acme/checkout", "path" => "payment.rb",
                                               "start_line" => 3, "end_line" => 3 })

          assert_match(/payment\.rb:1-9 \(of 9 lines\)/, text)
          assert_match(/   3\s+retry_budget\(amount\)/, text)
        end
      end

      test "fetch_file refuses secrets-shaped and traversal paths" do
        error = assert_raises(NativePack::Error) do
          @pack.fetch_file(environment_row: @row, arguments: { "repo" => "acme/checkout", "path" => ".env" })
        end
        assert_match(/not readable/, error.message)

        assert_raises(NativePack::Error) do
          @pack.fetch_file(environment_row: @row, arguments: { "repo" => "acme/checkout", "path" => "../outside.rb" })
        end
      end

      test "code_search returns path:line references and hides sensitive files" do
        with_fixture_clone do
          text = @pack.code_search(environment_row: @row,
                                   arguments: { "repo" => "acme/checkout", "pattern" => "retry_budget|SECRET" })

          assert_match(/payment\.rb:3:/, text)
          assert_no_match(/\.env/, text, "denylisted paths never appear in results")
        end
      end

      test "code_search reports zero matches readably" do
        with_fixture_clone do
          assert_equal "No matches.",
                       @pack.code_search(environment_row: @row,
                                         arguments: { "repo" => "acme/checkout", "pattern" => "nothing_matches_this" })
        end
      end

      test "blame attributes lines to their commits and points at the lookup tools" do
        with_fixture_clone do
          text = @pack.blame(environment_row: @row,
                             arguments: { "repo" => "acme/checkout", "path" => "payment.rb",
                                          "start_line" => 1, "end_line" => 6 })

          assert_match(/Tighten retry budget \(Grace Retries\)/, text)
          assert_match(/Add payment charging \(Ada Payments\)/, text)
          assert_match(/Use commit_lookup or pr_lookup/, text)
        end
      end

      test "blame validates its line range" do
        assert_raises(NativePack::Error) do
          @pack.blame(environment_row: @row,
                      arguments: { "repo" => "acme/checkout", "path" => "payment.rb",
                                   "start_line" => 9, "end_line" => 2 })
        end
      end

      private

      def with_fixture_clone
        fixture = FixtureRepo.create!
        clone_root = Dir.mktmpdir("clone-root")
        CloneManager.stubs(:root).returns(Pathname.new(clone_root))
        CloneManager.stubs(:remote_url).returns(fixture)
        yield
      ensure
        FileUtils.rm_rf(fixture) if fixture
        FileUtils.rm_rf(clone_root) if clone_root
      end
    end
  end
end
