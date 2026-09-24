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

      test "a deployment nobody has reported on yet reads as having no status" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments?per_page=3", token: "ghs_token").returns([
          { "id" => 9, "ref" => "v41", "environment" => "production", "created_at" => "2026-09-12T10:01:00Z" }
        ])
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments/9/statuses?per_page=1", token: "ghs_token")
                 .returns([])

        text = @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/checkout" })

        assert_match(/v41\s+no status\s+by unknown/, text)
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
        assert_no_match(/Abandoned spike/, text, "closed without merging is not a merge")
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

      test "fetch_file reads the file at the commit asked for, numbered, with a link pinned to that commit" do
        source = (1..9).map { |number| number == 3 ? "  retry_budget(amount)\n" : "  line #{number}\n" }.join
        GithubApp.stubs(:get).with("/repos/acme/checkout/contents/payment.rb?ref=a1b2c3", token: "ghs_token")
                 .returns("content" => Base64.encode64(source))

        text = @pack.fetch_file(environment_row: @row,
                                arguments: { "repo" => "acme/checkout", "path" => "payment.rb", "ref" => "a1b2c3",
                                             "start_line" => 3, "end_line" => 3 })

        assert_match(/payment\.rb:1-9 \(of 9 lines\) at a1b2c3/, text)
        assert_match(/   3\s+retry_budget\(amount\)/, text)
        assert_includes text, "https://github.com/acme/checkout/blob/a1b2c3/payment.rb#L1-L9"
      end

      test "fetch_file says plainly when the file is not there at that commit" do
        GithubApp.stubs(:get).raises(GithubApp::Error, "GitHub: Not Found")

        error = assert_raises(NativePack::Error) do
          @pack.fetch_file(environment_row: @row, arguments: { "repo" => "acme/checkout", "path" => "gone.rb", "ref" => "a1b2c3" })
        end
        assert_equal "No file at 'gone.rb' at a1b2c3.", error.message
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

      test "blame attributes the lines at a commit to the changes and pull requests that last touched them" do
        GithubApp.expects(:graphql).with do |_query, variables, token:|
          variables[:expression] == "a1b2c3" && variables[:path] == "payment.rb" && token == "ghs_token"
        end.returns("repository" => { "object" => { "blame" => { "ranges" => [
          blame_range(1, 2, "1111aaaa2222", "Add payment charging", "ada", nil),
          blame_range(3, 6, "3333bbbb4444", "Tighten retry budget", "grace", 412),
          blame_range(7, 40, "5555cccc6666", "Unrelated", "linus", nil)
        ] } } })

        text = @pack.blame(environment_row: @row,
                           arguments: { "repo" => "acme/checkout", "path" => "payment.rb", "ref" => "a1b2c3",
                                        "start_line" => 1, "end_line" => 6 })

        assert_match(/L3-6 .*3333bbbb4444 .*Tighten retry budget \(grace\) PR #412/, text)
        assert_match(/L1-2 .*Add payment charging \(ada\)/, text)
        assert_no_match(/Unrelated/, text, "a range outside the lines asked about is left out")
        assert_includes text, "https://github.com/acme/checkout/blob/a1b2c3/payment.rb#L1-L6"
      end

      test "running_commit names the last deploy that worked before the time, and the one to compare it with" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments?per_page=#{Github::DEPLOYMENT_CANDIDATES}", token: "ghs_token").returns([
          deployment(4, "after", "production", "2026-09-24T15:00:00Z"),
          deployment(3, "failed", "production", "2026-09-24T14:02:00Z"),
          deployment(2, "running", "production", "2026-09-24T13:00:00Z"),
          deployment(1, "previous", "production", "2026-09-23T10:00:00Z")
        ])
        # GitHub marks an older deployment inactive once a newer one goes out, so its success is further down.
        { 3 => [ "failure" ], 2 => [ "success" ], 1 => [ "inactive", "success" ] }.each do |id, states|
          GithubApp.stubs(:get).with("/repos/acme/checkout/deployments/#{id}/statuses?per_page=#{GithubApp::DEPLOYMENT_STATUS_LIMIT}", token: "ghs_token")
                   .returns(states.map { |state| { "state" => state, "created_at" => "2026-09-24T12:00:00Z" } })
        end

        text = @pack.running_commit(environment_row: @row, arguments: { "repo" => "acme/checkout", "at" => "2026-09-24T14:05:00Z" })

        assert_includes text, "Running in acme/checkout at 2026-09-24T14:05:00Z: running"
        assert_includes text, "Source: a deploy record"
        assert_includes text, "compare_commits with base previous and head running"
      end

      test "running_commit without a deploy record says it is a guess from the default branch" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/deployments?per_page=#{Github::DEPLOYMENT_CANDIDATES}", token: "ghs_token").returns([])
        GithubApp.stubs(:get).with("/repos/acme/checkout", token: "ghs_token").returns("default_branch" => "main")
        GithubApp.stubs(:get).with { |path, **| path.start_with?("/repos/acme/checkout/commits?") && path.include?("until=2026-09-24T14%3A05%3A00Z") }
                 .returns([ { "sha" => "tipsha", "commit" => { "committer" => { "date" => "2026-09-24T13:50:00Z" } } } ])
        GithubApp.stubs(:get).with { |path, **| path.start_with?("/repos/acme/checkout/commits?") && path.include?("until=2026-09-23T14%3A05%3A00Z") }
                 .returns([ { "sha" => "daybefore" } ])

        text = @pack.running_commit(environment_row: @row, arguments: { "repo" => "acme/checkout", "at" => "2026-09-24T14:05:00Z" })

        assert_includes text, "not known. There is no successful deploy record"
        assert_includes text, "Tip of main at that time: tipsha"
        assert_includes text, "not proof it was deployed"
        assert_includes text, "compare_commits with base daybefore and head tipsha"
      end

      test "compare_commits puts migrations and config first, names dependency bumps, owners and pull requests" do
        GithubApp.stubs(:get).with("/repos/acme/checkout/compare/base1...head1", token: "ghs_token").returns(
          "base_commit" => { "sha" => "base1" },
          "commits" => [ comparison_commit("head1", "Raise pool timeout") ],
          "files" => [
            { "filename" => "app/models/pool.rb", "status" => "modified", "additions" => 2, "deletions" => 1, "patch" => "@@ -1 +1 @@\n-a\n+b" },
            { "filename" => "config/database.yml", "status" => "modified", "additions" => 1, "deletions" => 1, "patch" => "@@\n-  pool: 20\n+  pool: 5" },
            { "filename" => "Gemfile.lock", "status" => "modified", "additions" => 1, "deletions" => 1, "patch" => "@@\n-    pg (1.4.0)\n+    pg (1.5.0)" }
          ]
        )
        GithubApp.stubs(:get).with("/repos/acme/checkout/commits/head1/pulls", token: "ghs_token").returns([
          { "number" => 412, "title" => "Raise pool timeout", "user" => { "login" => "grace" }, "html_url" => "https://github.com/acme/checkout/pull/412" }
        ])
        GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/reviews", token: "ghs_token").returns([ { "user" => { "login" => "ada" } } ])
        GithubApp.stubs(:get).with("/repos/acme/checkout/contents/.github/CODEOWNERS?ref=head1", token: "ghs_token")
                 .returns("content" => Base64.encode64("* @acme/app\nconfig/ @acme/platform\n"))

        text = @pack.compare_commits(environment_row: @row, arguments: { "repo" => "acme/checkout", "base" => "base1", "head" => "head1" })

        assert_operator text.index("Configuration:"), :<, text.index("Application code:"), "config is listed before code"
        assert_includes text, "pg 1.4.0 to 1.5.0"
        assert_includes text, "PR #412 Raise pool timeout by grace, reviewed by ada"
        assert_includes text, "@acme/platform: config/database.yml"
        assert_includes text, "https://github.com/acme/checkout/blob/head1/config/database.yml"
        assert_includes text, "+  pool: 5"
      end

      test "the new tools are declared read only" do
        definitions = Github.tool_definitions.index_by(&:name)

        [ Github::RUNNING_COMMIT, Github::CHANGES_BEFORE, Github::LIST_REPOSITORIES, "compare_commits" ].each do |name|
          assert definitions[name].read_only, name
        end
      end

      test "changes_before refuses a window it cannot use" do
        error = assert_raises(NativePack::Error) do
          @pack.changes_before(environment_row: @row, arguments: { "at" => "2026-09-24T14:05:00Z", "window_hours" => 0 })
        end
        assert_match(/window_hours/, error.message)
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

      def blame_range(from, to, sha, headline, login, pull_number)
        pulls = pull_number ? [ { "number" => pull_number, "title" => headline } ] : []
        { "startingLine" => from, "endingLine" => to,
          "commit" => { "oid" => sha, "committedDate" => "2026-09-20T10:00:00Z", "messageHeadline" => headline,
                        "author" => { "name" => login, "user" => { "login" => login } },
                        "associatedPullRequests" => { "nodes" => pulls } } }
      end

      def deployment(id, sha, environment, created_at)
        { "id" => id, "sha" => sha, "ref" => "main", "environment" => environment, "created_at" => created_at, "creator" => { "login" => "deployer" } }
      end

      def comparison_commit(sha, message)
        { "sha" => sha, "author" => { "login" => "grace" }, "commit" => { "message" => message, "author" => { "date" => "2026-09-24T13:00:00Z", "name" => "Grace" } } }
      end
    end
  end
end
