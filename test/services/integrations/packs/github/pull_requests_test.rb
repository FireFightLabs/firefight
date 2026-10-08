require "test_helper"

module Integrations
  module Packs
    class Github
      class PullRequestsTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "reads only read and every change goes through the gateway as a write" do
          reads = %w[list_pull_requests pr_lookup pull_request_diff]
          writes = %w[comment_on_pull_request reply_to_review_comment review_pull_request update_pull_request request_reviewers label_pull_request
                      close_pull_request reopen_pull_request merge_pull_request update_pull_request_branch]
          definitions = Github.tool_definitions.index_by(&:name)

          assert reads.all? { |name| definitions.fetch(name).read_only }
          assert writes.none? { |name| definitions.fetch(name).read_only }
        end

        test "a pull request is read with its reviews, review comments, checks, statuses and files, linked to its page" do
          stub_pull(412)
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/files?per_page=30", token: "ghs_token")
                   .returns([ { "filename" => "app/models/payment.rb", "additions" => 8, "deletions" => 2 } ])
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/reviews?per_page=100", token: "ghs_token")
                   .returns([ { "user" => { "login" => "ada" }, "state" => "CHANGES_REQUESTED", "submitted_at" => "2026-08-01T09:00:00Z", "body" => "Retry budget?" } ])
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/comments?per_page=100&sort=created&direction=desc", token: "ghs_token")
                   .returns([ { "id" => 77, "user" => { "login" => "ada" }, "path" => "app/models/payment.rb", "line" => 12, "body" => "Unbounded here",
                                "html_url" => "https://github.com/acme/checkout/pull/412#discussion_r77" } ])
          stub_checks("b" * 40)

          text = text_of(@pack.pr_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 }))

          assert_includes text, "PR #412: Fix payment retries"
          assert_includes text, "Branch: fix-retries -> main, head #{'b' * 12}"
          assert_includes text, "Can merge: yes"
          assert_includes text, "ada changes requested at 2026-08-01T09:00:00Z: Retry budget?"
          assert_includes text, "77 by ada on app/models/payment.rb:12: Unbounded here"
          assert_includes text, "Checks on #{'b' * 40}:\n  test: failure (GitHub Actions), 3 failed  https://github.com/acme/checkout/runs/5"
          assert_includes text, "Commit statuses, failure overall:\n  ci/deploy: failure, Deploy preview failed"
          assert_includes text, "app/models/payment.rb (+8 -2)"
          assert_includes text, "Retries were unbounded."
          assert text.end_with?("https://github.com/acme/checkout/pull/412")
        end

        test "a read that only adds to the answer says which permission would show it" do
          stub_pull(412)
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/files?per_page=30", token: "ghs_token").returns([])
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/reviews?per_page=100", token: "ghs_token").returns([])
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/comments?per_page=100&sort=created&direction=desc", token: "ghs_token").returns([])
          GithubApp.stubs(:get).with("/repos/acme/checkout/commits/#{'b' * 40}/check-runs?filter=latest&per_page=100", token: "ghs_token")
                   .raises(GithubApp::NotPermitted, "GitHub: Resource not accessible by integration")

          text = text_of(@pack.pr_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 }))

          assert_includes text, "Checks not shown: Firefight's GitHub App needs Checks read for them."
          assert_includes text, "Reviews: none."
        end

        test "a Dependabot update is read with the advisories it fixes" do
          stub_pull(9, "user" => { "login" => "dependabot[bot]" }, "title" => "Bump rack from 2.2.3 to 2.2.8", "body" => "Updates `rack-test` from 1 to 2")
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/9/files?per_page=30", token: "ghs_token").returns([])
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/9/reviews?per_page=100", token: "ghs_token").returns([])
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/9/comments?per_page=100&sort=created&direction=desc", token: "ghs_token").returns([])
          stub_checks("b" * 40)
          GithubApp.expects(:get).with("/repos/acme/checkout/dependabot/alerts?package=rack%2Crack-test&per_page=20", token: "ghs_token").returns([
            { "number" => 3, "state" => "open", "html_url" => "https://github.com/acme/checkout/security/dependabot/3",
              "dependency" => { "package" => { "name" => "rack", "ecosystem" => "rubygems" }, "manifest_path" => "Gemfile.lock" },
              "security_advisory" => { "ghsa_id" => "GHSA-xxxx", "cve_id" => "CVE-2026-1", "summary" => "Denial of service", "severity" => "high" },
              "security_vulnerability" => { "vulnerable_version_range" => "< 2.2.8", "first_patched_version" => { "identifier" => "2.2.8" } } }
          ])

          text = text_of(@pack.pr_lookup(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 9 }))

          assert_includes text, "Dependabot advisories for rack and rack-test:\n  #3 open  high  rack (rubygems) in Gemfile.lock  GHSA-xxxx CVE-2026-1  " \
                                "Denial of service  vulnerable < 2.2.8, fixed in 2.2.8  https://github.com/acme/checkout/security/dependabot/3"
        end

        test "pull requests are listed with the list API, and searched when an author, label or words are given" do
          GithubApp.expects(:get).with("/repos/acme/checkout/pulls?base=main&direction=desc&head=acme%3Afix&per_page=20&state=open", token: "ghs_token")
                   .returns([ pull(412) ])
          text = text_of(@pack.list_pull_requests(environment_row: @row, arguments: { "repo" => "acme/checkout", "base" => "main", "head" => "fix" }))
          assert_includes text, "#412 Fix payment retries  open  fix-retries -> main  by uros"
          assert text.end_with?("https://github.com/acme/checkout/pulls")

          query = { "order" => "desc", "per_page" => 5, "q" => "repo:acme/checkout is:pr is:closed author:dependabot[bot] label:\"security\" rack" }.to_query
          GithubApp.expects(:get).with("/search/issues?#{query}", token: "ghs_token")
                   .returns("items" => [ { "number" => 9, "title" => "Bump rack", "state" => "closed", "user" => { "login" => "dependabot[bot]" },
                                           "html_url" => "https://github.com/acme/checkout/pull/9", "labels" => [ { "name" => "security" } ] } ])
          text = text_of(@pack.list_pull_requests(environment_row: @row, arguments: { "repo" => "acme/checkout", "state" => "closed", "author" => "dependabot[bot]",
                                                                                      "label" => "security", "text" => "rack", "limit" => 5 }))
          assert_includes text, "#9 Bump rack  closed  by dependabot[bot]"
        end

        test "a diff lists each file with its patch, cut at a path when asked" do
          stub_pull(412)
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/files?per_page=100&page=1", token: "ghs_token").returns([
            { "filename" => "app/models/payment.rb", "status" => "modified", "additions" => 1, "deletions" => 1, "patch" => "@@ -1 +1 @@\n-a\n+b" },
            { "filename" => "docs/readme.md", "status" => "modified", "additions" => 1, "deletions" => 0, "patch" => "+c" }
          ])

          text = text_of(@pack.pull_request_diff(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "path" => "app/" }))

          assert_includes text, "PR #412 Fix payment retries in acme/checkout, 1 file under app/:"
          assert_includes text, "app/models/payment.rb (modified, +1 -1)\n@@ -1 +1 @@\n-a\n+b"
          assert_not_includes text, "readme"
          assert text.end_with?("https://github.com/acme/checkout/pull/412/files")
        end

        test "a comment goes on the pull request's conversation, with anything like a credential taken out" do
          stub_pull(412)
          GithubApp.expects(:write).with do |verb, path, body, token:|
            verb == :post && path == "/repos/acme/checkout/issues/412/comments" && token == "ghs_token" &&
              body[:body].start_with?("Rolled back. Token") && !body[:body].include?("ghp_#{'a' * 36}")
          end.returns("html_url" => "https://github.com/acme/checkout/pull/412#issuecomment-1")

          result = @pack.comment_on_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "body" => "Rolled back. Token ghp_#{'a' * 36}" })

          assert_includes text_of(result), "Commented on PR #412 Fix payment retries in acme/checkout."
          assert text_of(result).end_with?("https://github.com/acme/checkout/pull/412#issuecomment-1")
        end

        test "a reply goes in the review comment's thread" do
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/pulls/412/comments/77/replies", { body: "Fixed in the next commit" }, token: "ghs_token")
                   .returns("path" => "app/models/payment.rb", "html_url" => "https://github.com/acme/checkout/pull/412#discussion_r78")

          result = @pack.reply_to_review_comment(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "comment_id" => 77, "body" => "Fixed in the next commit" })

          assert_includes text_of(result), "Replied to review comment 77 on PR #412 in acme/checkout on app/models/payment.rb."
        end

        test "a review is pinned to the head commit, with line comments, and asking for changes needs words" do
          stub_pull(412)
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/pulls/412/reviews",
                                         { commit_id: "b" * 40, event: "REQUEST_CHANGES", body: "Bound the retries",
                                           comments: [ { path: "app/models/payment.rb", line: 12, side: "RIGHT", body: "Here" } ] }, token: "ghs_token")
                   .returns("html_url" => "https://github.com/acme/checkout/pull/412#pullrequestreview-5")

          result = @pack.review_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "event" => "request_changes", "body" => "Bound the retries",
                                                                                 "comments" => [ { "path" => "app/models/payment.rb", "line" => 12, "body" => "Here" } ] })

          assert_includes text_of(result), "Requested changes on PR #412 Fix payment retries in acme/checkout at #{'b' * 12}, with 1 line comment."
          assert_equal "body is required", assert_raises(NativePack::Error) {
            @pack.review_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "event" => "comment" })
          }.message
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/pulls/412/reviews", { commit_id: "b" * 40, event: "APPROVE" }, token: "ghs_token").returns({})
          assert_includes text_of(@pack.review_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "event" => "approve" })), "Approved PR #412"
        end

        test "a title, description or base changes, and nothing is sent without one" do
          stub_pull(412)
          GithubApp.expects(:write).with(:patch, "/repos/acme/checkout/pulls/412", { title: "Bound payment retries", base: "release" }, token: "ghs_token")
                   .returns(pull(412).merge("title" => "Bound payment retries"))

          result = @pack.update_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "title" => "Bound payment retries", "base" => "release" })

          assert_includes text_of(result), "Changed its title and its base to release on PR #412 Bound payment retries in acme/checkout."
          assert_equal "Give a title, body or base to change.",
                       assert_raises(NativePack::Error) { @pack.update_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 }) }.message
        end

        test "reviewers are asked by login and team slug" do
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/pulls/412/requested_reviewers", { reviewers: [ "ada" ], team_reviewers: [ "platform" ] }, token: "ghs_token")
                   .returns(pull(412))

          result = @pack.request_reviewers(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "reviewers" => [ "@ada" ], "team_reviewers" => [ "acme/platform" ] })

          assert_includes text_of(result), "Asked ada and the platform team to review PR #412 Fix payment retries in acme/checkout."
          assert_match "is not a GitHub login", assert_raises(NativePack::Error) {
            @pack.request_reviewers(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "reviewers" => [ "not a login" ] })
          }.message
        end

        test "labels are added only when the repository has them, and one it does not carry is said" do
          stub_pull(412)
          GithubApp.stubs(:get).with("/repos/acme/checkout/labels?per_page=100&page=1", token: "ghs_token").returns([ { "name" => "incident" }, { "name" => "hotfix" } ])
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/issues/412/labels", { labels: [ "incident" ] }, token: "ghs_token").returns([])
          GithubApp.expects(:write).with(:delete, "/repos/acme/checkout/issues/412/labels/needs%20review", token: "ghs_token").raises(GithubApp::NotFound, "GitHub answered 404: Label does not exist")

          text = text_of(@pack.label_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "add" => [ "incident" ], "remove" => [ "needs review" ] }))

          assert_includes text, "Added incident to PR #412 Fix payment retries in acme/checkout. PR #412 Fix payment retries did not have needs review."
          GithubApp.expects(:write).never
          assert_match "acme/checkout has no label sev1, and Firefight never makes a label by adding one. Its labels are incident, hotfix.",
                       assert_raises(PolicyRefusal) { @pack.label_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "add" => "sev1" }) }.message
        end

        test "closing posts the reason first, and a closed or merged one is left alone" do
          stub_pull(412)
          sequence = sequence("close")
          GithubApp.expects(:write).with(:post, "/repos/acme/checkout/issues/412/comments", { body: "Superseded by #413" }, token: "ghs_token").in_sequence(sequence).returns({})
          GithubApp.expects(:write).with(:patch, "/repos/acme/checkout/pulls/412", { state: "closed" }, token: "ghs_token").in_sequence(sequence).returns({})

          text = text_of(@pack.close_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "comment" => "Superseded by #413" }))
          assert_includes text, "Closed PR #412 Fix payment retries in acme/checkout without merging it, with a comment saying why. reopen_pull_request opens it again."

          stub_pull(413, "state" => "closed", "merged_at" => "2026-08-01T10:00:00Z")
          assert_equal "PR #413 in acme/checkout is already merged.",
                       assert_raises(NativePack::Error) { @pack.close_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 413 }) }.message
          assert_equal "PR #413 in acme/checkout is merged, so it cannot be reopened.",
                       assert_raises(NativePack::Error) { @pack.reopen_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 413 }) }.message
        end

        test "a closed pull request reopens" do
          stub_pull(414, "state" => "closed")
          GithubApp.expects(:write).with(:patch, "/repos/acme/checkout/pulls/414", { state: "open" }, token: "ghs_token").returns({})

          assert_includes text_of(@pack.reopen_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 414 })), "Reopened PR #414"
        end

        test "a pull request merges at the head that was read, only when GitHub says it can" do
          stub_pull(412)
          GithubApp.expects(:write).with(:put, "/repos/acme/checkout/pulls/412/merge", { merge_method: "squash", sha: "b" * 40 }, token: "ghs_token")
                   .returns("merged" => true, "sha" => "c" * 40)

          text = text_of(@pack.merge_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412, "method" => "squash" }))

          assert_includes text, "Merged PR #412 Fix payment retries in acme/checkout into main by squash, as #{'c' * 12}. Its head was #{'b' * 12}."
          assert text.end_with?("https://github.com/acme/checkout/pull/412")
        end

        test "a pull request that is not ready is never sent to merge, and the refusal is Firefight's check with why" do
          GithubApp.expects(:write).never
          {
            { "mergeable" => false, "mergeable_state" => "dirty" } => "it conflicts with its base. fix_code with this pull_request, asked to merge the base in",
            { "mergeable" => true, "mergeable_state" => "blocked" } => "a branch protection rule blocks it",
            { "mergeable" => true, "mergeable_state" => "behind" } => "its branch is behind its base, so update_pull_request_branch brings it up to date first",
            { "mergeable" => nil, "mergeable_state" => "unknown" } => "GitHub has not worked out yet whether it can merge",
            { "draft" => true } => "it is a draft"
          }.each do |state, words|
            stub_pull(412, state)
            error = assert_raises(PolicyRefusal) { @pack.merge_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 }) }
            assert_match "Firefight checked PR #412 in acme/checkout before merging and does not merge it now, because #{words}", error.message
          end
        end

        test "a conflict on a pull request Firefight opened is Halon's to fix with the person's yes, and on anyone else's is offered" do
          stub_pull(412, "mergeable" => false, "mergeable_state" => "dirty")
          workspace = @integration.workspace
          words = @pack.send(:merge_words, GithubApp.get("/repos/acme/checkout/pulls/412", token: "ghs_token"))
          assert_match "so offer that to the person and run it once they agree", words

          session = CodeAgentSession.create!(workspace: workspace, provider: "anthropic", model: "m", repository: "acme/checkout", budget_micros: 1,
                                             expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, pull_request_number: 412)
          assert CodeAgentSession.opened_pull_request?(workspace, "acme/checkout", 412)
          own = @pack.send(:merge_words, GithubApp.get("/repos/acme/checkout/pulls/412", token: "ghs_token"), own: true)
          assert_match "Firefight opened it, so fixing it is yours", own
          assert session
        end

        test "a pull request's standing reads mergeable, the checks that failed and the reviewers whose latest review asks for changes" do
          stub_pull(412, "mergeable" => nil, "mergeable_state" => "unknown")
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412", token: "ghs_token")
                   .returns(pull(412, "mergeable" => nil, "mergeable_state" => "unknown")).then.returns(pull(412, "mergeable" => false, "mergeable_state" => "dirty"))
          stub_checks("b" * 40)
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/reviews?per_page=100", token: "ghs_token").returns([
            { "id" => 1, "user" => { "login" => "ada" }, "state" => "CHANGES_REQUESTED", "body" => "Retry budget?" },
            { "id" => 2, "user" => { "login" => "lin" }, "state" => "CHANGES_REQUESTED", "body" => "Name it." },
            { "id" => 3, "user" => { "login" => "lin" }, "state" => "APPROVED", "body" => "" }
          ])
          @pack.expects(:sleep).with(Github::PullRequests::SETTLE_WAIT).once

          status = @pack.pull_request_status(@row, repository: "acme/checkout", number: 412, settle: true)

          assert_equal [ Integrations::PullRequests::OPEN, Integrations::PullRequests::CONFLICTED ], [ status.state, status.mergeable ]
          assert_includes status.failing_checks.map(&:name), "test"
          assert_equal [ "ada" ], status.reviews.map(&:reviewer), "a reviewer who approved since no longer asks"
          assert_equal Integrations::PullRequests::PROBLEMS, status.problems
          assert_match "The code host says PR #412 conflicts with main, so it cannot merge.", status.words
        end

        test "a merged pull request reads as merged and needs no more reads" do
          stub_pull(412, "state" => "closed", "merged_at" => "2026-08-02T10:00:00Z")
          GithubApp.expects(:get).with { |path, **| path.include?("check-runs") }.never

          status = @pack.pull_request_status(@row, repository: "acme/checkout", number: 412)

          assert_equal Integrations::PullRequests::MERGED, status.state
          assert_empty status.problems
        end

        test "a merge GitHub refuses because the head moved is said with what to do" do
          stub_pull(412)
          GithubApp.stubs(:write).raises(GithubApp::Error, "GitHub answered 409: Head branch was modified. Review and try the merge again.")

          error = assert_raises(NativePack::Error) { @pack.merge_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 }) }

          assert_equal "GitHub did not merge PR #412 in acme/checkout: GitHub answered 409: Head branch was modified. Review and try the merge again. " \
                       "Read it again with pr_lookup to see why.", error.message
        end

        test "a branch is brought up to date from the head that was read" do
          stub_pull(412)
          GithubApp.expects(:write).with(:put, "/repos/acme/checkout/pulls/412/update-branch", { expected_head_sha: "b" * 40 }, token: "ghs_token")
                   .returns("message" => "Updating pull request branch.")

          assert_includes text_of(@pack.update_pull_request_branch(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 })),
                          "GitHub is merging main into fix-retries for PR #412 Fix payment retries in acme/checkout."
        end

        test "GitHub refusing for a missing permission names every permission the tool needs, and a missing pull request says why it may be" do
          stub_pull(412)
          GithubApp.stubs(:write).raises(GithubApp::NotPermitted, "GitHub answered 403: Resource not accessible by integration")

          error = assert_raises(NativePack::Error) { @pack.merge_pull_request(environment_row: @row, arguments: { "repo" => "acme/checkout", "number" => 412 }) }
          assert_equal "GitHub refused this: GitHub answered 403: Resource not accessible by integration. Firefight's GitHub App needs Contents read and " \
                       "write and Pull requests read on this installation for that. An owner of the GitHub account grants it under Settings, GitHub " \
                       "Apps, by accepting the App's new permissions.", error.message

          GithubApp.stubs(:get).with("/repos/acme/secret/pulls/1", token: "ghs_token").raises(GithubApp::NotFound, "GitHub: Not Found")
          error = assert_raises(NativePack::Error) { @pack.close_pull_request(environment_row: @row, arguments: { "repo" => "acme/secret", "number" => 1 }) }
          assert_equal "GitHub has no pull request 1 in acme/secret. GitHub answers not found for a repository this connection's GitHub App was not given, " \
                       "and list_repositories names the ones it was.", error.message
        end

        private

        def pull(number, overrides = {})
          { "number" => number, "title" => "Fix payment retries", "state" => "open", "draft" => false, "merged_at" => nil, "user" => { "login" => "uros" },
            "head" => { "ref" => "fix-retries", "sha" => "b" * 40, "repo" => { "full_name" => "acme/checkout" } }, "base" => { "ref" => "main" },
            "mergeable" => true, "mergeable_state" => "clean", "changed_files" => 1, "additions" => 8, "deletions" => 2, "body" => "Retries were unbounded.",
            "updated_at" => "2026-08-01T10:00:00Z", "html_url" => "https://github.com/acme/checkout/pull/#{number}" }.merge(overrides)
        end

        def stub_pull(number, overrides = {})
          GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/#{number}", token: "ghs_token").returns(pull(number, overrides))
        end

        def stub_checks(sha)
          GithubApp.stubs(:get).with("/repos/acme/checkout/commits/#{sha}/check-runs?filter=latest&per_page=100", token: "ghs_token").returns("check_runs" => [
            { "name" => "lint", "status" => "completed", "conclusion" => "success", "html_url" => "https://github.com/acme/checkout/runs/4", "head_sha" => sha },
            { "name" => "test", "status" => "completed", "conclusion" => "failure", "app" => { "name" => "GitHub Actions" }, "output" => { "title" => "3 failed" },
              "html_url" => "https://github.com/acme/checkout/runs/5", "head_sha" => sha }
          ])
          GithubApp.stubs(:get).with("/repos/acme/checkout/commits/#{sha}/status?per_page=100", token: "ghs_token").returns(
            "state" => "failure", "sha" => sha, "statuses" => [ { "context" => "ci/deploy", "state" => "failure", "description" => "Deploy preview failed", "target_url" => "https://ci.example.com/1" } ]
          )
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
