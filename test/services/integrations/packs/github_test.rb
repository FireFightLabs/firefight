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

      test "recent_deployments names what shipped, where, and how it ended" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments?per_page=3", token: "ghs_token").returns([
          { "id" => 9, "ref" => "v41", "environment" => "production",
            "created_at" => "2026-09-12T10:01:00Z", "creator" => { "login" => "uros" } },
          { "id" => 8, "ref" => "v40", "environment" => "production",
            "created_at" => "2026-09-11T16:20:00Z", "creator" => { "login" => "ada" } }
        ])
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments/9/statuses?per_page=1", token: "ghs_token")
                 .returns([ { "state" => "success" } ])
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments/8/statuses?per_page=1", token: "ghs_token")
                 .returns([ { "state" => "failure" } ])

        text = @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/checkout" })

        assert_match(/2026-09-12T10:01:00Z\s+production\s+v41\s+success\s+by uros/, text)
        assert_match(/v40\s+failure\s+by ada/, text)
      end

      test "recent_deployments can be limited to one deployment environment" do
        GithubApp.expects(:get)
                 .with("/repos/acme/checkout/deployments?environment=production&per_page=3", token: "ghs_token")
                 .returns([])

        assert_match(/No deployments recorded/,
                     @pack.recent_deployments(environment_row: @row,
                                              arguments: { "repo" => "acme/checkout",
                                                           "deployment_environment" => "production" }))
      end

      test "a deployment whose status cannot be read still lists what shipped" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments?per_page=3", token: "ghs_token").returns([
          { "id" => 9, "ref" => "v41", "environment" => "production", "created_at" => "2026-09-12T10:01:00Z" }
        ])
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments/9/statuses?per_page=1", token: "ghs_token")
                 .raises(GithubApp::Error, "GitHub: Not Found")

        text = @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/checkout" })

        assert_match(/v41\s+state unavailable\s+by unknown/, text)
      end

      test "merged_pull_requests keeps only the ones that actually merged" do
        GithubApp.stubs(:get).with(closed_pulls_path, token: "ghs_token").returns([
          { "number" => 412, "title" => "Fix payment retries", "merged_at" => "2026-09-12T09:40:00Z",
            "user" => { "login" => "uros" }, "base" => { "ref" => "main" } },
          { "number" => 411, "title" => "Abandoned spike", "merged_at" => nil,
            "user" => { "login" => "ada" }, "base" => { "ref" => "main" } }
        ])

        text = @pack.merged_pull_requests(environment_row: @row, arguments: { "repo" => "acme/checkout" })

        assert_match(/PR #412\s+Fix payment retries\s+merged 2026-09-12T09:40:00Z by uros into main/, text)
        assert_no_match(/Abandoned spike/, text, "a closed pull request that never merged is not a change")
      end

      test "merged_pull_requests can be windowed to what merged since a time" do
        GithubApp.stubs(:get).with(closed_pulls_path, token: "ghs_token").returns([
          { "number" => 412, "title" => "Shipped today", "merged_at" => "2026-09-12T09:40:00Z",
            "user" => { "login" => "uros" }, "base" => { "ref" => "main" } },
          { "number" => 380, "title" => "Shipped last month", "merged_at" => "2026-08-01T09:40:00Z",
            "user" => { "login" => "ada" }, "base" => { "ref" => "main" } }
        ])

        text = @pack.merged_pull_requests(
          environment_row: @row, arguments: { "repo" => "acme/checkout", "since" => "2026-09-12T00:00:00Z" }
        )

        assert_match(/Shipped today/, text)
        assert_no_match(/Shipped last month/, text)
      end

      test "merged_pull_requests says so when nothing merged in the window" do
        GithubApp.stubs(:get).with(closed_pulls_path, token: "ghs_token").returns([])

        text = @pack.merged_pull_requests(
          environment_row: @row, arguments: { "repo" => "acme/checkout", "since" => "2026-09-12T00:00:00Z" }
        )

        assert_match(/No pull requests merged since 2026-09-12T00:00:00Z/, text)
      end

      test "since must be a time it can parse" do
        error = assert_raises(NativePack::Error) do
          @pack.merged_pull_requests(environment_row: @row,
                                     arguments: { "repo" => "acme/checkout", "since" => "last tuesday" })
        end

        assert_match(/ISO 8601/, error.message)
      end

      test "both new reads are declared as read only tools" do
        names = Github.tool_definitions.select(&:read_only).map(&:name)

        assert_includes names, "recent_deployments"
        assert_includes names, "merged_pull_requests"
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

      def closed_pulls_path
        "/repos/acme/checkout/pulls?state=closed&sort=updated&direction=desc&per_page=#{Github::CLOSED_CANDIDATES}"
      end

      def with_fixture_clone(&block)
        FixtureRepo.with_clone_env(&block)
      end
    end
  end
end
