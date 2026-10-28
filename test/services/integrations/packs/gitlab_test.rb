require "test_helper"

module Integrations
  module Packs
    class GitlabTest < ActiveSupport::TestCase
      PROJECT = "/projects/acme%2Fplatform%2Fweb".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
        @row = @integration.integration_environments.create!
        Gitlab.store_credentials!(@row, Gitlab::TOKEN => " glpat-token ")
        @pack = Gitlab.new(@integration, box_key: "investigation-1")
      end

      test "the token is the one credential, the address an optional connect field that must be https, and only the test runner and pipeline changes write" do
        assert_equal "glpat-token", ConnectionSettings.of(@row.reload).credential(Gitlab::TOKEN)
        assert_equal [ Gitlab::TOKEN ], Gitlab.credential_fields.map(&:key)
        assert_equal %w[run_tests retry_pipeline run_pipeline cancel_pipeline retry_job play_job cancel_job redeploy approve_deployment stop_environment
                        comment_on_merge_request edit_merge_request_comment review_merge_request reply_to_merge_request_thread resolve_merge_request_thread],
                     Gitlab.tool_definitions.reject(&:read_only).map(&:name),
                     "only the sandbox's test runner, the pipeline, job, deployment and environment changes and the merge request comments write"
        address = IntegrationProvider.find(Gitlab::PROVIDER_KEY).connect_fields.sole
        assert_equal [ Gitlab::URL, true ], [ address.key, address.optional ]
        assert_nil address.refusal("https://gitlab.example.com/gitlab")
        assert_match "can hold only an https address", address.refusal("http://gitlab.example.com")
        assert_match "can hold only an https address", address.refusal("https://user:secret@gitlab.example.com")
      end

      test "a token is checked with GitLab before anything is saved, and a personal one missing a scope is named" do
        assert_equal "Paste an access token.", Gitlab.credential_refusal({ Gitlab::TOKEN => " " })

        GitlabApi.any_instance.stubs(:get).with("/projects", { "membership" => true, "simple" => true, "per_page" => 1 }).raises(GitlabApi::Refused, "GitLab answered 401: 401 Unauthorized")
        assert_match "GitLab refused this token: GitLab answered 401: 401 Unauthorized. Check it is active", Gitlab.credential_refusal({ Gitlab::TOKEN => "bad" })

        GitlabApi.any_instance.stubs(:get).with("/projects", { "membership" => true, "simple" => true, "per_page" => 1 }).returns([])
        GitlabApi.any_instance.stubs(:get).with("/personal_access_tokens/self").returns("scopes" => [ "read_api" ])
        assert_equal "This token is missing the read_repository scope. Create one with read_api and read_repository.", Gitlab.credential_refusal({ Gitlab::TOKEN => "t" })

        GitlabApi.any_instance.stubs(:get).with("/personal_access_tokens/self").returns("scopes" => [ "api" ])
        assert_nil Gitlab.credential_refusal({ Gitlab::TOKEN => "t" })

        GitlabApi.any_instance.stubs(:get).with("/personal_access_tokens/self").raises(GitlabApi::Error, "GitLab answered 400: This endpoint requires token type to be a personal access token")
        assert_nil Gitlab.credential_refusal({ Gitlab::TOKEN => "group-token" }), "a group or project token cannot say its scopes, so none is assumed missing"

        assert_match "must start with https", Gitlab.credential_refusal({ Gitlab::TOKEN => "t" }, fields: { Gitlab::URL => "http://gitlab.example.com" })
      end

      test "a merge request says who wrote, merged and approved it, its files, and links to its page" do
        stub_get("#{PROJECT}/merge_requests/42", "iid" => 42, "title" => "Raise pool size", "state" => "merged", "merged_at" => "2026-10-01T10:00:00Z",
                                                 "merge_user" => { "username" => "ana" }, "author" => { "username" => "uros" }, "source_branch" => "pool",
                                                 "target_branch" => "main", "changes_count" => "1", "description" => "Pool ran dry.",
                                                 "web_url" => "https://gitlab.com/acme/platform/web/-/merge_requests/42")
        stub_list("#{PROJECT}/merge_requests/42/diffs", [ { "new_path" => "config/database.yml", "diff" => "@@ -1 +1 @@\n-pool: 5\n+pool: 20\n" } ])
        stub_get("#{PROJECT}/merge_requests/42/approvals", "approved_by" => [ { "user" => { "username" => "lea" } } ])

        text = call(:mr_lookup, "repo" => "acme/platform/web", "iid" => 42)

        assert_includes text, "MR !42: Raise pool size"
        assert_includes text, "merged at 2026-10-01T10:00:00Z by ana"
        assert_includes text, "Approved by: lea"
        assert_includes text, "config/database.yml (modified, +1 -1)"
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/merge_requests/42")
      end

      test "a project must be a path with its groups, and a commit a SHA" do
        assert_match "path with its groups", assert_raises(NativePack::Error) { call(:commit_lookup, "repo" => "../etc", "sha" => "abc123") }.message
        assert_match "commit SHA", assert_raises(NativePack::Error) { call(:commit_lookup, "repo" => "acme/web", "sha" => "main;rm") }.message
      end

      test "deployments are read newest first, each with its environment, outcome and job" do
        GitlabApi.any_instance.expects(:get).with("#{PROJECT}/deployments", { "order_by" => "id", "sort" => "desc", "per_page" => 2, "environment" => "production" })
                 .returns([ { "id" => 9, "created_at" => "2026-10-01T10:00:00Z", "environment" => { "name" => "production" }, "ref" => "main",
                              "sha" => "a" * 40, "status" => "success", "user" => { "username" => "ana" },
                              "deployable" => { "id" => 77, "web_url" => "https://gitlab.com/acme/platform/web/-/jobs/77" } } ])

        result = @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/platform/web", "deployment_environment" => "production", "limit" => 2 })
        text = result["content"].first["text"]

        assert text.start_with?("2026-10-01T10:00:00Z  production  main  #{'a' * 12}  success  by ana  deployment 9  job 77 https://gitlab.com/acme/platform/web/-/jobs/77\n")
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/environments")
        run = Capabilities::History.runs_of(result).sole
        assert_equal [ "deployment-9", "deployment to production", Capabilities::History::SUCCEEDED, "https://gitlab.com/acme/platform/web/-/jobs/77" ],
                     [ run.id, run.name, run.status, run.url ]
      end

      test "deployments are kept as data, a finished one ending when its job did" do
        GitlabApi.any_instance.expects(:get).with("#{PROJECT}/deployments", { "order_by" => "id", "sort" => "desc", "per_page" => 10, "environment" => nil })
                 .returns([ { "id" => 10, "created_at" => "2026-10-01T11:00:00Z", "updated_at" => "2026-10-01T11:01:00Z", "ref" => "main",
                              "sha" => "b" * 40, "status" => "running", "deployable" => { "id" => 78 } },
                            { "id" => 9, "created_at" => "2026-10-01T10:00:00Z", "updated_at" => "2026-10-01T10:09:00Z", "ref" => "main",
                              "sha" => "a" * 40, "status" => "success", "deployable" => { "id" => 77, "finished_at" => "2026-10-01T10:08:00Z" } },
                            { "id" => 8, "created_at" => "2026-10-01T09:00:00Z", "updated_at" => "2026-10-01T09:05:00Z", "ref" => "main",
                              "sha" => "c" * 40, "status" => "failed" } ])

        running, succeeded, failed = Capabilities::Deploys.deploys_of(@pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/platform/web" }))

        assert_equal [ "10", "b" * 40, "main", Capabilities::History::RUNNING, nil, nil ],
                     [ running.id, running.commit, running.branch, running.status, running.live, running.finished_at ]
        assert_equal [ "9", Capabilities::History::SUCCEEDED, Time.utc(2026, 10, 1, 10), Time.utc(2026, 10, 1, 10, 8) ],
                     [ succeeded.id, succeeded.status, succeeded.started_at, succeeded.finished_at ]
        assert_equal [ "8", Capabilities::History::FAILED, Time.utc(2026, 10, 1, 9, 5) ], [ failed.id, failed.status, failed.finished_at ]
      end

      test "merged merge requests are the newest merged first, by when each was merged" do
        stub_get("#{PROJECT}/merge_requests", { "state" => "merged", "order_by" => "updated_at", "sort" => "desc", "per_page" => 50, "merged_after" => nil },
                 [ { "iid" => 1, "title" => "Older", "merged_at" => "2026-09-01T00:00:00Z", "target_branch" => "main", "web_url" => "u1" },
                   { "iid" => 2, "title" => "Newer", "merged_at" => "2026-09-02T00:00:00Z", "target_branch" => "main", "web_url" => "u2", "merge_user" => { "username" => "ana" } } ])

        lines = call(:merged_merge_requests, "repo" => "acme/platform/web").lines

        assert_equal [ "MR !2", "MR !1" ], lines.map { |line| line[/MR !\d+/] }
        assert_includes lines.first, "by ana into main"
      end

      test "the running commit is the last successful deployment to production before the time, with the one before to compare" do
        at = "2026-10-01T12:00:00Z"
        stub_get("#{PROJECT}/deployments", { "status" => "success", "order_by" => "finished_at", "sort" => "desc", "finished_before" => at, "per_page" => 30 },
                 [ deployment(3, "staging", "c" * 40), deployment(2, "production", "b" * 40), deployment(1, "production", "a" * 40) ])

        text = call(:running_commit, "repo" => "acme/platform/web", "at" => at)

        assert_includes text, "Running in acme/platform/web at 2026-10-01T12:00:00Z: #{'b' * 40}"
        assert_includes text, "compare_commits with base #{'a' * 40} and head #{'b' * 40}"
      end

      test "without a deployment the running commit is a guess from the default branch, and it says so" do
        at = "2026-10-01T12:00:00Z"
        stub_get("#{PROJECT}/deployments", { "status" => "success", "order_by" => "finished_at", "sort" => "desc", "finished_before" => at, "per_page" => 30 }, [])
        stub_get(PROJECT, { "default_branch" => "main" })
        stub_get("#{PROJECT}/repository/commits", { "ref_name" => "main", "until" => at, "per_page" => 1 }, [ { "id" => "h" * 40, "committed_date" => at } ])
        stub_get("#{PROJECT}/repository/commits", { "ref_name" => "main", "until" => "2026-09-30T12:00:00Z", "per_page" => 1 }, [ { "id" => "g" * 40 } ])

        text = call(:running_commit, "repo" => "acme/platform/web", "at" => at)

        assert_includes text, "not proof it was deployed"
        assert_includes text, "compare_commits with base #{'g' * 40} and head #{'h' * 40}"
      end

      test "a comparison groups the files, names the merge requests with their approvers and the owners, and gives every diff" do
        stub_get("#{PROJECT}/repository/compare", { "from" => "v1", "to" => "v2" }, {
          "commits" => [ { "id" => "c" * 40, "title" => "Bump rack", "author_name" => "Uros", "authored_date" => "2026-10-01T09:00:00Z", "committed_date" => "2026-10-01T09:00:00Z" } ],
          "diffs" => [ { "new_path" => "Gemfile.lock", "diff" => "-    rack (3.0.0)\n+    rack (3.1.0)\n" },
                       { "new_path" => "db/migrate/1_add.rb", "new_file" => true, "diff" => "+class Add\n" } ],
          "compare_timeout" => true, "web_url" => "https://gitlab.com/acme/platform/web/-/compare/v1...v2"
        })
        stub_get("#{PROJECT}/repository/commits/#{'c' * 40}/merge_requests", [ { "iid" => 5, "title" => "Bump rack", "author" => { "username" => "uros" }, "web_url" => "u5" } ])
        stub_get("#{PROJECT}/merge_requests/5/approvals", "approved_by" => [])
        GitlabApi.any_instance.stubs(:text).with("#{PROJECT}/repository/files/CODEOWNERS/raw", { "ref" => "c" * 40 }).returns("db/ @data-team\n")

        text = call(:compare_commits, "repo" => "acme/platform/web", "base" => "v1", "head" => "v2")
        range = Integrations::Capabilities::Comparison.of(@pack.compare_commits(environment_row: @row, arguments: { "repo" => "acme/platform/web", "base" => "v1", "head" => "v2" }))

        assert_equal [ 1, [ "#{'c' * 12} Bump rack" ], { "migration" => 1, "dependency" => 1 }, [ "db/migrate/1_add.rb" ], false ],
                     [ range.commits, range.titles, range.kinds, range.migrations, range.complete ], "a comparison GitLab stopped early is not complete"

        assert_includes text, "1 commits, 2 files changed. Base v1, head #{'c' * 40}. GitLab stopped comparing before the end"
        assert text.index("Database migrations") < text.index("Dependencies"), "migrations come first"
        assert_includes text, "MR !5 Bump rack by uros, no approvals u5"
        assert_includes text, "@data-team: db/migrate/1_add.rb"
        assert_includes text, "db/migrate/1_add.rb https://gitlab.com/acme/platform/web/-/blob/#{'c' * 40}/db/migrate/1_add.rb"
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/compare/v1...v2")
      end

      test "a file is read at the commit its ref points to, and its link is pinned there with GitLab's line range" do
        stub_get("#{PROJECT}/repository/files/app%2Fmodels%2Fpool.rb", { "ref" => "main" },
                 "content" => Base64.strict_encode64("one\ntwo\nthree\n"), "commit_id" => "d" * 40)

        text = call(:fetch_file, "repo" => "acme/platform/web", "path" => "app/models/pool.rb", "ref" => "main", "start_line" => 2, "end_line" => 2)

        assert_includes text, "   2  two"
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/blob/#{'d' * 40}/app/models/pool.rb#L1-3")
        assert_match "may hold secrets", assert_raises(PolicyRefusal) { call(:fetch_file, "repo" => "acme/platform/web", "path" => ".env") }.message
      end

      test "blame numbers GitLab's ranges from the first line asked and names the merge requests behind them" do
        stub_get("#{PROJECT}/repository/files/app%2Fmodels%2Fpool.rb/blame", { "ref" => "HEAD", "range[start]" => 10, "range[end]" => 13 }, [
          { "commit" => { "id" => "e" * 40, "message" => "Shrink pool\n", "committed_date" => "2026-09-30T08:00:00Z", "author_name" => "Ana" }, "lines" => [ "a", "b" ] },
          { "commit" => { "id" => "f" * 40, "message" => "Add pool", "committed_date" => "2026-01-01T08:00:00Z", "author_name" => "Uros" }, "lines" => [ "c", "d" ] }
        ])
        stub_get("#{PROJECT}/repository/commits/#{'e' * 40}/merge_requests", [ { "iid" => 7, "title" => "Shrink pool.", "web_url" => "u7" } ])
        stub_get("#{PROJECT}/repository/commits/#{'f' * 40}/merge_requests", [ { "iid" => 8, "title" => "Add pool", "web_url" => "u8" } ])

        text = call(:blame, "repo" => "acme/platform/web", "path" => "app/models/pool.rb", "start_line" => 10, "end_line" => 13)

        assert_includes text, "L10-11       #{'e' * 12} 2026-09-30T08:00:00Z Shrink pool (Ana)"
        assert_includes text, "L12-13       #{'f' * 12}"
        assert_includes text, "Merge requests: !7 Shrink pool u7 and !8 Add pool u8."
      end

      test "pipelines are listed newest first with their page" do
        stub_get("#{PROJECT}/pipelines", { "ref" => "main", "status" => "failed", "updated_after" => nil, "per_page" => 10 },
                 [ { "id" => 31, "status" => "failed", "ref" => "main", "sha" => "a" * 40, "source" => "push", "created_at" => "t", "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/31" } ])

        assert_equal "t  pipeline 31  failed  main  #{'a' * 12}  push  https://gitlab.com/acme/platform/web/-/pipelines/31",
                     call(:pipelines, "repo" => "acme/platform/web", "ref" => "main", "status" => "failed")
        assert_match "status must be one of", assert_raises(NativePack::Error) { call(:pipelines, "repo" => "acme/platform/web", "status" => "broken") }.message
      end

      test "CI runs read each pipeline for when it started and finished, narrowed to a pipeline by name" do
        stub_get("#{PROJECT}/pipelines", { "per_page" => 10, "name" => "release" }, [])
        stub_get("#{PROJECT}/pipelines", { "per_page" => 50 }, [
          { "id" => 32, "iid" => 12, "status" => "running", "name" => "Release", "ref" => "main" },
          { "id" => 31, "iid" => 11, "status" => "success", "name" => nil, "ref" => "main" },
          { "id" => 30, "iid" => 10, "status" => "success", "name" => "Release", "ref" => "main" }
        ])
        stub_get("#{PROJECT}/pipelines/32", { "id" => 32, "iid" => 12, "status" => "running", "name" => "Release", "ref" => "main", "sha" => "a" * 40,
                                              "source" => "web", "started_at" => "2026-10-02T10:00:00Z", "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/32" })
        stub_get("#{PROJECT}/pipelines/30", { "id" => 30, "iid" => 10, "status" => "success", "name" => "Release", "ref" => "main", "sha" => "b" * 40,
                                              "source" => "web", "started_at" => "2026-10-01T10:00:00Z", "finished_at" => "2026-10-01T10:12:00Z" })

        result = @pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web", "name" => "release" })
        runs = Capabilities::History.runs_of(result)

        assert_equal [ [ "32", "12", "running", nil ], [ "30", "10", "succeeded", 720 ] ], runs.map { |run| [ run.id, run.number, run.status, run.seconds ] }
        assert_equal 720, result["structuredContent"]["usual_seconds"]
        assert_includes result["content"].first["text"], "https://gitlab.com/acme/platform/web/-/pipelines"
      end

      test "a name GitLab knows whole, a status and a source go to GitLab's own filters" do
        GitlabApi.any_instance.expects(:get).with("#{PROJECT}/pipelines", { "status" => "manual", "source" => "web", "per_page" => 10, "name" => "Deploy production" })
                 .returns([ { "id" => 33, "status" => "manual", "name" => "Deploy production", "ref" => "main" } ])
        stub_get("#{PROJECT}/pipelines/33", { "id" => 33, "status" => "manual", "name" => "Deploy production", "ref" => "main", "created_at" => "2026-10-01T10:00:00Z" })

        run = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web", "name" => "Deploy production",
                                                                                               "status" => "manual", "source" => "web", "limit" => 10 })).sole

        assert_equal [ "33", Capabilities::History::WAITING ], [ run.id, run.status ]
        assert_not run.finished?
        assert_match "status must be one of", assert_raises(NativePack::Error) { call(:ci_runs, "repo" => "acme/platform/web", "status" => "broken") }.message
      end

      test "a name no pipeline has reads the deployments as runs, a blocked one waiting for approval, and one is read back by its id" do
        stub_get("#{PROJECT}/pipelines", { "per_page" => 10, "name" => "production" }, [])
        stub_get("#{PROJECT}/pipelines", { "per_page" => 50 }, [ { "id" => 31, "status" => "success", "ref" => "main" } ])
        blocked = deployment(4, "production", "a" * 40).merge("status" => "blocked", "created_at" => "2026-10-04T00:00:00Z")
        stub_get("#{PROJECT}/deployments", { "order_by" => "id", "sort" => "desc", "environment" => "production", "per_page" => 10 }, [])
        stub_get("#{PROJECT}/deployments", { "order_by" => "id", "sort" => "desc", "per_page" => 50 }, [ blocked ])
        stub_get("#{PROJECT}/deployments/4", blocked)

        listed = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web", "name" => "production" })).sole
        followed = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web", "run" => "deployment-4" })).sole

        assert_equal [ "deployment-4", "deployment to production", Capabilities::History::WAITING ], [ listed.id, listed.name, listed.status ],
                     "with none matched whole, the newest of every environment are read, more than asked for"
        assert_includes followed.detail, "waiting for approval, approve_deployment gives it"
      end

      test "a pipeline without a name is called by its branch" do
        stub_get("#{PROJECT}/pipelines", { "per_page" => 10 }, [ { "id" => 31, "status" => "failed", "ref" => "main" } ])
        stub_get("#{PROJECT}/pipelines/31", { "id" => 31, "status" => "failed", "ref" => "main", "created_at" => "2026-10-01T10:00:00Z" })

        run = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web" })).sole

        assert_equal [ "pipeline on main", "failed" ], [ run.name, run.status ]
      end

      test "one pipeline read by its id carries its jobs, a failed one with why and how its log is read, and a job allowed to fail left out" do
        stub_get("#{PROJECT}/pipelines/31", { "id" => 31, "status" => "running", "ref" => "main", "created_at" => "2026-10-01T10:00:00Z", "web_url" => "p31" })
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/pipelines/31/jobs", {}, pages: Gitlab::Pipelines::JOB_PAGES).returns([ [
          { "id" => 2, "stage" => "test", "name" => "rspec", "status" => "failed", "failure_reason" => "script_failure",
            "started_at" => "2026-10-01T10:01:00Z", "finished_at" => "2026-10-01T10:02:00Z", "web_url" => "j2" },
          { "id" => 3, "stage" => "test", "name" => "lint", "status" => "failed", "allow_failure" => true },
          { "id" => 1, "stage" => "deploy", "name" => "web", "status" => "running" }
        ], false ])
        stub_list("#{PROJECT}/pipelines/31/trigger_jobs", [])

        run = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web", "run" => "31" })).sole

        assert_equal [ "test / rspec", "deploy / web" ], run.parts.map(&:name)
        failed = run.first_failed_part
        assert_equal [ "with script failure", 60 ], [ failed.detail, failed.seconds ]
        assert_equal({ "tool" => "job_log", "arguments" => { "repo" => "acme/platform/web", "job_id" => 2 } }, failed.log)
      end

      test "a trigger job and the child pipeline it started are followed too, and a manual job says it waits for someone to start it" do
        stub_get("#{PROJECT}/pipelines/31", { "id" => 31, "status" => "running", "ref" => "main", "created_at" => "2026-10-01T10:00:00Z" })
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/pipelines/31/jobs", {}, pages: Gitlab::Pipelines::JOB_PAGES)
                 .returns([ [ { "id" => 1, "stage" => "deploy", "name" => "production", "status" => "manual" } ], false ])
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/pipelines/31/trigger_jobs").raises(GitlabApi::NotFound, "404")
        stub_list("#{PROJECT}/pipelines/31/bridges", [ { "id" => 5, "stage" => "build", "name" => "services", "status" => "running",
                                                         "downstream_pipeline" => { "id" => 40, "status" => "running", "web_url" => "p40" } } ])
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/pipelines/40/jobs", {}, pages: Gitlab::Pipelines::JOB_PAGES)
                 .returns([ [ { "id" => 41, "stage" => "test", "name" => "api", "status" => "failed", "failure_reason" => "script_failure" } ], false ])

        run = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web", "run" => "31" })).sole

        assert_equal [ "deploy / production", "build / services", "services > test / api" ], run.parts.map(&:name)
        assert_equal [ Capabilities::History::WAITING, "waiting for someone to start it, play_job starts job 1" ], [ run.parts.first.status, run.parts.first.detail ]
        assert_equal [ "p40", "starts pipeline 40, running" ], [ run.parts.second.url, run.parts.second.detail ]
        assert_equal "41", run.first_failed_part.id
      end

      test "one job is retried, a manual one started and a running one canceled, each refused when its state does not fit" do
        stub_get("#{PROJECT}/jobs/7", { "id" => 7, "stage" => "deploy", "name" => "web", "status" => "failed", "ref" => "main", "commit" => { "short_id" => "abc12345" } })
        stub_get("#{PROJECT}/jobs/8", { "id" => 8, "stage" => "deploy", "name" => "prod", "status" => "manual", "ref" => "main", "commit" => { "short_id" => "abc12345" } })
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/jobs/7/retry").returns("id" => 70, "status" => "pending", "web_url" => "j70")
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/jobs/8/play", { "job_variables_attributes" => [ { "key" => "TARGET", "value" => "eu" } ] })
                 .returns("id" => 8, "status" => "pending")
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/jobs/8/cancel").returns("status" => "canceling")

        assert_includes call(:retry_job, "repo" => "acme/platform/web", "job_id" => 7), "Job 7 deploy/web in acme/platform/web runs again as job 70, on main at abc12345. It is pending."
        assert_includes call(:play_job, "repo" => "acme/platform/web", "job_id" => 8, "variables" => { "TARGET" => "eu" }), "Started Job 8 deploy/prod in acme/platform/web with TARGET"
        assert_includes call(:cancel_job, "repo" => "acme/platform/web", "job_id" => 8), "the rest of its pipeline goes on as it was"
        assert_match "not a manual job", assert_raises(NativePack::Error) { call(:play_job, "repo" => "acme/platform/web", "job_id" => 7) }.message
        assert_match "already finished", assert_raises(NativePack::Error) { call(:cancel_job, "repo" => "acme/platform/web", "job_id" => 7) }.message
      end

      test "an earlier deployment is deployed again by retrying the job that made it, and one no job made is refused" do
        stub_get("#{PROJECT}/deployments/9", deployment(9, "production", "a" * 40).merge("deployable" => { "id" => 77, "stage" => "deploy", "name" => "web", "status" => "success" }))
        stub_get("#{PROJECT}/deployments/8", deployment(8, "production", "b" * 40).merge("deployable" => nil))
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/jobs/77/retry").returns("id" => 90, "status" => "pending", "web_url" => "j90")

        assert_includes call(:redeploy, "repo" => "acme/platform/web", "deployment" => 9),
                        "Deploying the deployment 9 of #{'a' * 12} to production again as job 90, a new run of deploy/web. It is pending."
        assert_match "was not made by a job", assert_raises(Integrations::PolicyRefusal) { call(:redeploy, "repo" => "acme/platform/web", "deployment" => 8) }.message
      end

      test "a deployment waiting for approval is approved or rejected, and one not waiting is refused" do
        stub_get("#{PROJECT}/deployments/9", deployment(9, "production", "a" * 40).merge("status" => "blocked", "deployable" => { "web_url" => "j77" }))
        stub_get("#{PROJECT}/deployments/8", deployment(8, "production", "b" * 40).merge("status" => "success"))
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/deployments/9/approval", { "status" => "approved", "comment" => "Fix verified" })
                 .returns("user" => { "username" => "firefight-bot" }, "status" => "approved")

        assert_includes call(:approve_deployment, "repo" => "acme/platform/web", "deployment" => 9, "decision" => "approve", "comment" => "Fix verified"),
                        "Approved the deployment 9 of #{'a' * 12} to production as firefight-bot. Its job goes on once every approval rule has its approvals. A manual job still waits to be started, which play_job does."
        assert_match "not waiting for approval", assert_raises(Integrations::PolicyRefusal) {
          call(:approve_deployment, "repo" => "acme/platform/web", "deployment" => 8, "decision" => "approve")
        }.message
      end

      test "environments say who may deploy and how many approvals a deploy needs, and one is stopped with or without its stop job" do
        stub_list("#{PROJECT}/environments", [ { "id" => 1, "name" => "production", "state" => "available", "tier" => "production", "external_url" => "https://web.example.com" },
                                               { "id" => 2, "name" => "review/x", "state" => "available" } ])
        stub_get("#{PROJECT}/protected_environments", [ { "name" => "production", "deploy_access_levels" => [ { "access_level_description" => "Maintainers" } ],
                                                          "required_approval_count" => 0, "approval_rules" => [ { "required_approvals" => 2 } ] } ])
        stub_get("#{PROJECT}/environments/2", { "id" => 2, "name" => "review/x", "state" => "available" })
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/environments/2/stop", { "force" => true }).returns("state" => "stopped")

        text = call(:list_environments, "repo" => "acme/platform/web")

        assert_includes text, "  production (id 1), available, production tier, only Maintainers deploy, needs 2 approvals  https://web.example.com\n  review/x (id 2), available"
        assert_includes call(:stop_environment, "repo" => "acme/platform/web", "environment_id" => 2, "force" => true), "Stopping review/x in acme/platform/web, without running its stop job. It is stopped."
      end

      test "releases, one release by its tag, and tags are read with their pages" do
        release = { "tag_name" => "v1.2.0", "name" => "Spring", "released_at" => "2026-10-01T00:00:00Z", "commit" => { "short_id" => "abc12345" },
                    "description" => "Faster checkout", "_links" => { "self" => "https://gitlab.com/acme/platform/web/-/releases/v1.2.0" },
                    "assets" => { "links" => [ { "name" => "binary", "url" => "https://example.com/bin" } ] } }
        stub_get("#{PROJECT}/releases", { "per_page" => 10 }, [ release ])
        stub_get("#{PROJECT}/releases/v1.2.0", release)
        stub_get("#{PROJECT}/repository/tags", { "order_by" => "updated", "sort" => "desc", "search" => "^v1", "per_page" => 10 },
                 [ { "name" => "v1.2.0", "commit" => { "id" => "c" * 40, "committed_date" => "2026-10-01T00:00:00Z" }, "message" => "Spring", "release" => {} } ])

        assert_includes call(:list_releases, "repo" => "acme/platform/web"), "  v1.2.0  Spring  released 2026-10-01T00:00:00Z  commit abc12345  https://gitlab.com/acme/platform/web/-/releases/v1.2.0"
        looked_up = call(:release_lookup, "repo" => "acme/platform/web", "tag" => "v1.2.0")
        assert_includes looked_up, "Files and links:\n  binary  https://example.com/bin\n\nFaster checkout"
        assert_includes call(:list_tags, "repo" => "acme/platform/web", "search" => "^v1"), "  v1.2.0  #{'c' * 12}  2026-10-01T00:00:00Z  Spring  has a release"
        assert Gitlab.tool_definitions.select { |definition| %w[list_releases release_lookup list_tags list_environments].include?(definition.name) }.all?(&:read_only)
      end

      test "a pipeline's jobs say why each failed and link to the pipeline" do
        stub_list("#{PROJECT}/pipelines/31/jobs", [ { "id" => 2, "stage" => "test", "name" => "rspec", "status" => "failed", "failure_reason" => "script_failure",
                                                      "duration" => 61.4, "web_url" => "j2" },
                                                    { "id" => 1, "stage" => "build", "name" => "image", "status" => "success", "web_url" => "j1" } ], query: {})

        text = call(:pipeline_jobs, "repo" => "acme/platform/web", "pipeline_id" => 31)

        assert_includes text, "  build / image  success  job 1  j1\n  test / rspec  failed (script failure)  61s  job 2  j2"
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/pipelines/31")
      end

      test "a job's log is the newest failed job's end, without colours or section markers, filtered as asked" do
        stub_get("#{PROJECT}/jobs", { "scope" => [ "failed" ], "per_page" => 50 }, [
          { "id" => 8, "ref" => "feature", "finished_at" => "2026-10-01T09:00:00Z" },
          { "id" => 7, "ref" => "main", "stage" => "test", "name" => "rspec", "status" => "failed", "failure_reason" => "script_failure",
            "finished_at" => "2026-10-01T08:00:00Z", "commit" => { "short_id" => "abc12345" }, "web_url" => "https://gitlab.com/acme/platform/web/-/jobs/7" }
        ])
        GitlabApi.any_instance.stubs(:text).with("#{PROJECT}/jobs/7/trace").returns(
          "section_start:1:prepare\r\e[0K\e[32mPreparing\e[0m\nRunning specs\nFailure: pool exhausted\nsection_end:2:prepare\r\e[0K\nERROR: Job failed\n"
        )

        text = call(:job_log, "repo" => "acme/platform/web", "ref" => "main", "exclude" => "Running")

        assert_includes text, "Job 7 test/rspec in acme/platform/web, failed, script failure, on main at abc12345"
        assert_includes text, "Its log, 3 lines:\nPreparing\nFailure: pool exhausted\nERROR: Job failed"
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/jobs/7")
        stub_get("#{PROJECT}/jobs/7", { "id" => 7, "name" => "rspec", "web_url" => "j7" })
        assert_match "regex is not a regular expression", assert_raises(NativePack::Error) { call(:job_log, "repo" => "acme/platform/web", "job_id" => 7, "regex" => "(") }.message
      end

      test "with no failed job that fits, the log says so rather than reading another" do
        stub_get("#{PROJECT}/jobs", { "scope" => [ "failed" ], "per_page" => 50 }, [ { "id" => 8, "ref" => "feature" } ])

        assert_equal "No failed job in acme/platform/web on main among its newest 50 failed jobs.", call(:job_log, "repo" => "acme/platform/web", "ref" => "main")
      end

      test "CI status names the latest pipeline's failed jobs, when the branch last passed, and what each environment last deployed" do
        stub_get(PROJECT, { "default_branch" => "main" })
        stub_get("#{PROJECT}/pipelines", { "ref" => "main", "per_page" => 10 }, [
          { "id" => 33, "status" => "failed", "sha" => "b" * 40, "source" => "push", "created_at" => "t3", "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/33" },
          { "id" => 32, "status" => "failed" }, { "id" => 31, "status" => "success", "created_at" => "t1" }
        ])
        stub_get("#{PROJECT}/pipelines/33/jobs", { "scope" => [ "failed" ], "per_page" => 100 }, [ { "id" => 9, "stage" => "test", "name" => "rspec", "status" => "failed", "web_url" => "j9" } ])
        stub_get("#{PROJECT}/environments", { "states" => "available", "per_page" => 100 }, [ { "id" => 4, "name" => "staging" }, { "id" => 3, "name" => "production", "external_url" => "https://acme.com" } ])
        stub_get("#{PROJECT}/environments/3", "last_deployment" => { "status" => "success", "sha" => "a" * 40, "ref" => "main", "created_at" => "t0", "user" => { "username" => "ana" } })
        stub_get("#{PROJECT}/environments/4", "last_deployment" => nil)

        text = call(:ci_status, "repo" => "acme/platform/web")

        assert_includes text, "Latest pipeline on main: 33, failed, commit #{'b' * 12}"
        assert_includes text, "test / rspec  failed  job 9  j9"
        assert_includes text, "The last 3 pipelines, newest first: failed, failed, success. It last passed in pipeline 31 at t1."
        assert_includes text, "  production https://acme.com: success #{'a' * 12} (main) at t0 by ana\n  staging: nothing deployed yet"
        assert text.end_with?("https://gitlab.com/acme/platform/web/-/pipelines/33")
      end

      test "a pipeline's failed and canceled jobs are retried with its page, and one that passed is left as it is" do
        stub_get("#{PROJECT}/pipelines/33", { "id" => 33, "status" => "failed", "ref" => "main", "sha" => "b" * 40, "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/33" })
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/pipelines/33/retry").returns("id" => 33, "status" => "pending", "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/33")

        text = call(:retry_pipeline, "repo" => "acme/platform/web", "pipeline_id" => 33)

        assert_equal "Retrying the failed and canceled jobs of pipeline 33 in acme/platform/web, on main at #{'b' * 12}. It is pending. " \
                     "pipeline_jobs with its pipeline_id, or ci_status, follows it.\nOpen this in GitLab, and give the person this link with what you found: https://gitlab.com/acme/platform/web/-/pipelines/33", text

        stub_get("#{PROJECT}/pipelines/31", { "id" => 31, "status" => "success" })
        assert_equal "Pipeline 31 in acme/platform/web passed, so it has no failed or canceled jobs to retry. run_pipeline runs a new one.",
                     assert_raises(NativePack::Error) { call(:retry_pipeline, "repo" => "acme/platform/web", "pipeline_id" => 31) }.message
      end

      test "a pipeline runs on the default branch unless a ref is named, with variables and inputs as GitLab takes them" do
        stub_get(PROJECT, { "default_branch" => "main" })
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/pipeline", { "ref" => "main", "variables" => [ { "key" => "DEPLOY_TARGET", "value" => "eu" } ], "inputs" => { "smoke" => true } })
                 .returns("id" => 61, "status" => "created", "sha" => "c" * 40, "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/61")

        text = call(:run_pipeline, "repo" => "acme/platform/web", "variables" => { "DEPLOY_TARGET" => "eu" }, "inputs" => { "smoke" => true })

        assert_equal "Started pipeline 61 on main at #{'c' * 12} in acme/platform/web with DEPLOY_TARGET. It is created. " \
                     "pipeline_jobs with its pipeline_id, or ci_status, follows it.\nOpen this in GitLab, and give the person this link with what you found: https://gitlab.com/acme/platform/web/-/pipelines/61", text

        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/pipeline", { "ref" => "v1.2.0" }).returns("id" => 62, "status" => "created", "web_url" => "u62")
        assert_match "Started pipeline 62 on v1.2.0", call(:run_pipeline, "repo" => "acme/platform/web", "ref" => "v1.2.0")
        assert_equal "variables must be an object of names and values", assert_raises(NativePack::Error) { call(:run_pipeline, "repo" => "acme/platform/web", "variables" => "A=1") }.message
      end

      test "a running pipeline is canceled, and a finished one is said to have nothing to cancel, since GitLab answers 200 either way" do
        stub_get("#{PROJECT}/pipelines/34", { "id" => 34, "status" => "running", "ref" => "main", "sha" => "d" * 40, "web_url" => "https://gitlab.com/acme/platform/web/-/pipelines/34" })
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/pipelines/34/cancel").returns("id" => 34, "status" => "canceling")

        assert_match "Canceling pipeline 34 in acme/platform/web, on main at #{'d' * 12}. It is canceling.", call(:cancel_pipeline, "repo" => "acme/platform/web", "pipeline_id" => 34)

        stub_get("#{PROJECT}/pipelines/33", { "id" => 33, "status" => "failed" })
        assert_equal "Pipeline 33 in acme/platform/web already finished, failed, so there is nothing to cancel.",
                     assert_raises(NativePack::Error) { call(:cancel_pipeline, "repo" => "acme/platform/web", "pipeline_id" => 33) }.message
      end

      test "GitLab refusing a change is said with what it needs" do
        stub_get("#{PROJECT}/pipelines/33", { "id" => 33, "status" => "failed" })
        GitlabApi.any_instance.stubs(:post).raises(GitlabApi::Refused, "GitLab answered 403: insufficient_scope")

        assert_equal "GitLab refused to retry pipeline 33 in acme/platform/web: GitLab answered 403: insufficient_scope. Running, retrying or canceling a pipeline " \
                     "needs a token with the api scope, from someone who may run pipelines in the project, and on a protected branch someone allowed to merge or push to it.",
                     assert_raises(NativePack::Error) { call(:retry_pipeline, "repo" => "acme/platform/web", "pipeline_id" => 33) }.message
      end

      test "the map holds every project the token sees, and the infrastructure files in them, read through the tree and files API" do
        projects = [
          { "id" => 1, "path_with_namespace" => "acme/platform/infra", "default_branch" => "main", "web_url" => "https://gitlab.com/acme/platform/infra",
            "namespace" => { "full_path" => "acme/platform" } },
          { "id" => 2, "path_with_namespace" => "acme/old", "default_branch" => "main", "archived" => true, "web_url" => "u", "namespace" => { "full_path" => "acme" } }
        ]
        GitlabApi.any_instance.stubs(:list).with("/projects", { "membership" => true, "order_by" => "id", "sort" => "asc" }, pages: 10).returns([ projects, false ])
        GitlabApi.any_instance.stubs(:list).with("/projects/acme%2Fplatform%2Finfra/repository/tree", { "recursive" => true, "ref" => "main" }, pages: 50)
                 .returns([ [ { "type" => "blob", "path" => "dns.tf", "id" => "1" }, { "type" => "blob", "path" => "huge.tf", "id" => "2" },
                              { "type" => "tree", "path" => "k8s", "id" => "3" }, { "type" => "blob", "path" => "README.md", "id" => "4" } ], false ])
        GitlabApi.any_instance.stubs(:head).with("/projects/acme%2Fplatform%2Finfra/repository/files/dns.tf", { "ref" => "main" }).returns(Http::Answer.new(status: 200, body: {}, headers: { "x-gitlab-size" => "40" }))
        GitlabApi.any_instance.stubs(:head).with("/projects/acme%2Fplatform%2Finfra/repository/files/huge.tf", { "ref" => "main" }).returns(Http::Answer.new(status: 200, body: {}, headers: { "x-gitlab-size" => "900000" }))
        GitlabApi.any_instance.stubs(:text).with("/projects/acme%2Fplatform%2Finfra/repository/files/dns.tf/raw", { "ref" => "main" }).returns(%(resource "cloudflare_record" "app" {}))

        snapshot = @pack.map_of(@row)

        assert_equal [ [ "gitlab", "acme/platform", ResourceMap::KIND_REPOSITORY, "acme/platform/infra" ], [ "gitlab", "acme", ResourceMap::KIND_REPOSITORY, "acme/old" ] ],
                     snapshot.resources.map(&:key)
        file = snapshot.code_files.sole
        assert_equal [ "acme/platform/infra", "dns.tf", "Terraform", "gitlab", "https://gitlab.com/acme/platform/infra/-/blob/main/dns.tf" ],
                     [ file.repository, file.path, file.tool, file.provider, file.url ]
        assert_includes snapshot.gaps.map(&:text), "1 infrastructure file in acme/platform/infra is over 200 KB and was not read."
        assert_empty snapshot.code_read, "a repository with a file left unread is not read in full"
      end

      test "a change re-reads one project with its infrastructure files, and only GitLab's not found takes it away" do
        project = { "id" => 1, "path_with_namespace" => "acme/platform/infra", "default_branch" => "main", "web_url" => "https://gitlab.com/acme/platform/infra",
                    "namespace" => { "full_path" => "acme/platform" } }
        GitlabApi.any_instance.stubs(:get).with("/projects/acme%2Fplatform%2Finfra").returns(project)
        GitlabApi.any_instance.stubs(:list).with("/projects/acme%2Fplatform%2Finfra/repository/tree", { "recursive" => true, "ref" => "main" }, pages: 50)
                 .returns([ [ { "type" => "blob", "path" => "dns.tf", "id" => "1" } ], false ])
        GitlabApi.any_instance.stubs(:head).returns(Http::Answer.new(status: 200, body: {}, headers: { "x-gitlab-size" => "40" }))
        GitlabApi.any_instance.stubs(:text).with("/projects/acme%2Fplatform%2Finfra/repository/files/dns.tf/raw", { "ref" => "main" }).returns(%(resource "cloudflare_record" "app" {}))
        scope = ResourceMap::Scope.new(account: "acme/platform", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/platform/infra")

        snapshot = @pack.map_refresh(@row, scope)

        assert_equal [ [ "gitlab", "acme/platform", ResourceMap::KIND_REPOSITORY, "acme/platform/infra" ] ], snapshot.resources.map(&:key)
        assert_equal [ "dns.tf" ], snapshot.code_files.map(&:path)
        assert_equal [ "acme/platform/infra" ], snapshot.code_read

        GitlabApi.any_instance.stubs(:get).with("/projects/acme%2Fgone").raises(GitlabApi::NotFound, "GitLab answered 404: 404 Project Not Found")
        assert_equal [ [ "gitlab", "acme", ResourceMap::KIND_REPOSITORY, "acme/gone" ] ], @pack.map_refresh(@row, scope.with(account: "acme", external_id: "acme/gone")).gone
        GitlabApi.any_instance.stubs(:get).with("/projects/acme%2Fodd").raises(GitlabApi::Refused, "GitLab answered 403: 403 Forbidden")
        assert_raises(GitlabApi::Refused) { @pack.map_refresh(@row, scope.with(external_id: "acme/odd")) }
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(account: "acme")), "a namespace is read by a sweep"
      end

      test "a project list cut short at its cap is a gap that holds the repositories back, so none is taken as gone" do
        GitlabApi.any_instance.stubs(:list).with("/projects", { "membership" => true, "order_by" => "id", "sort" => "asc" }, pages: 10)
                 .returns([ [ { "id" => 1, "path_with_namespace" => "acme/web", "default_branch" => nil, "web_url" => "u", "namespace" => { "full_path" => "acme" } } ], true ])

        snapshot = @pack.map_of(@row)

        assert_equal [ [ "Only the first 1 projects were listed.", [ ResourceMap::KIND_REPOSITORY ] ] ], snapshot.gaps.map { |gap| [ gap.text, gap.kinds ] }
        assert_equal [ ResourceMap::KIND_REPOSITORY ], snapshot.unread_kinds
      end

      test "a broken token makes the health check fail with GitLab's words" do
        GitlabApi.any_instance.stubs(:get).raises(GitlabApi::Refused, "GitLab answered 401: 401 Unauthorized")

        assert_equal "GitLab answered 401: 401 Unauthorized", assert_raises(NativePack::Error) { @pack.check_health!(@row) }.message
      end

      test "the sandbox fetches from the same instance as oauth2 and never follows a redirect, at the checked address for a workspace's own" do
        remote = @pack.send(:code_remote, @row)
        assert_equal [ "gitlab.com", "https://gitlab.com/acme/web.git", "oauth2", "glpat-token", [ "http.followRedirects=false" ] ],
                     [ remote.host, remote.url("acme/web"), remote.user, remote.token.call, remote.options ]
        assert_equal "gitlab.com:acme/web", remote.key("acme/web")
        assert_match(/\Agitlab\.com__acme\.web-\h{10}\z/, remote.stored_name("acme/web"))

        @row.store_fields!(Gitlab::URL => "https://gitlab.example.com")
        Addrinfo.stubs(:getaddrinfo).returns([ stub(ip_address: "203.0.113.7") ])
        assert_includes @pack.send(:code_remote, @row.reload).options, "http.curloptResolve=gitlab.example.com:443:203.0.113.7"
      end

      test "a merge request's address on this connection's instance names its project and number, and no other host's does" do
        assert_equal [ "acme/platform/web", 42 ], @pack.pull_request_at(@row, "https://gitlab.com/acme/platform/web/-/merge_requests/42")
        assert_nil @pack.pull_request_at(@row, "https://github.com/acme/web/pull/42")

        @row.store_fields!(Gitlab::URL => "https://gitlab.example.com")
        assert_equal [ "acme/web", 7 ], @pack.pull_request_at(@row.reload, "https://gitlab.example.com/acme/web/-/merge_requests/7/diffs")
        assert_nil @pack.pull_request_at(@row, "https://gitlab.com/acme/web/-/merge_requests/7")
        assert_nil @pack.pull_request_at(@row, "http://gitlab.example.com/acme/web/-/merge_requests/7"), "another scheme is another address"
        assert_nil @pack.pull_request_at(@row, "https://gitlab.example.com:8443/acme/web/-/merge_requests/7"), "another port is another address"
      end

      test "the paths a merge request changes are read from every page of its diffs, a renamed file under both names" do
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/merge_requests/42/diffs", {}, pages: Gitlab::FLAG_FILE_PAGES)
                 .returns([ [ { "new_path" => "app/a.rb", "old_path" => "app/a.rb" }, { "new_path" => ".gitlab-ci.yml", "old_path" => "ci.yml", "renamed_file" => true } ], false ])

        assert_equal [ "app/a.rb", ".gitlab-ci.yml", "ci.yml" ], @pack.pull_request_paths(@row, repository: "acme/platform/web", number: 42)

        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/merge_requests/42/diffs", {}, pages: Gitlab::FLAG_FILE_PAGES).returns([ [], true ])
        error = assert_raises(Integrations::Error) { @pack.pull_request_paths(@row, repository: "acme/platform/web", number: 42) }
        assert_match "more files than GitLab lists", error.message
      end

      test "the newest comments are read back oldest first with every name of their author, leaving out GitLab's own and older ones" do
        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/42").returns("web_url" => "https://gitlab.com/acme/platform/web/-/merge_requests/42")
        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/42/notes", { "sort" => "desc", "order_by" => "created_at", "per_page" => 100 }).returns([
          { "id" => 3, "body" => "I can't read this repository.", "author" => { "username" => "project_7_bot_1", "id" => 77 }, "created_at" => "2026-10-27T10:00:05Z" },
          { "id" => 2, "system" => true, "body" => "added 1 commit", "author" => { "username" => "lea", "id" => 5 }, "created_at" => "2026-10-27T10:00:04Z" },
          { "id" => 1, "body" => "Older", "author" => { "username" => "lea", "id" => 5 }, "created_at" => "2026-10-27T09:00:00Z" }
        ])

        result = @pack.list_merge_request_comments(environment_row: @row, arguments: { "repo" => "acme/platform/web", "iid" => 42, "since" => "2026-10-27T10:00:00Z" })

        comment = Gitlab.review_posted(Integrations::PullRequestReviews::CONVERSATION, result.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::FACTS)).sole
        assert_equal [ "3", "https://gitlab.com/acme/platform/web/-/merge_requests/42#note_3", [ "project_7_bot_1", "77" ] ], [ comment.reference, comment.url, comment.authors ]
        assert Gitlab.tool_definitions.find { |tool| tool.name == "list_merge_request_comments" }.read_only
      end

      test "a moment that is not a time is refused in words" do
        error = assert_raises(Integrations::Error) { @pack.list_merge_request_comments(environment_row: @row, arguments: { "repo" => "acme/platform/web", "iid" => 42, "since" => "2026-13-45T99:00:00Z" }) }
        assert_equal "since must be a time in ISO 8601", error.message
      end

      test "a flag is a note on the merge request" do
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/merge_requests/42/notes", { "body" => "Look here." }).returns("id" => 1)

        @pack.flag_pull_request(@row, repository: "acme/platform/web", number: 42, body: "Look here.")
      end

      test "a check GitLab failed on its side is raised as it came, so it is tried again" do
        failed = GitlabApi::Error.new("GitLab answered 503").tap { |error| error.http_status = 503 }
        GitlabApi.any_instance.stubs(:post).raises(failed)
        check = Integrations::ReviewHost::Check.new(state: Integrations::ReviewHost::CHECK_FAILING, description: "Open.", url: nil)

        raised = assert_raises(GitlabApi::Error) { @pack.set_review_check(@row, repository: "acme/platform/web", sha: "a" * 40, check: check) }
        assert Integrations::ReviewHost.retryable?(raised)
      end

      test "how a merge request ended: who closed it, its commits oldest first, and the notes people wrote, never GitLab's own" do
        GitlabApi.any_instance.stubs(:get).with("#{PROJECT}/merge_requests/42").returns("state" => "closed", "closed_by" => { "username" => "lea" })
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/merge_requests/42/commits", {}, pages: 3).returns([ [
          { "id" => "b1", "author_name" => "Lea", "author_email" => "lea@acme.test", "message" => "Fix", "parent_ids" => [ "a1" ] },
          { "id" => "a1", "author_name" => "Halon", "author_email" => CodeAgentSession::COMMIT_EMAIL, "message" => "Change", "parent_ids" => [ "z" ] }
        ], false ])
        GitlabApi.any_instance.stubs(:list).with("#{PROJECT}/merge_requests/42/notes", { "sort" => "desc", "order_by" => "created_at" }).returns([ [
          { "system" => true, "body" => "closed", "author" => { "username" => "lea" } },
          { "body" => "Generated files are never hand edited", "author" => { "username" => "lea" } },
          { "body" => "Pipeline passed", "author" => { "username" => "project_7_bot_1" } }
        ], false ])

        outcome = @pack.pull_request_outcome(@row, repository: "acme/platform/web", number: 42)

        assert_equal [ Integrations::ReviewHost::STATE_CLOSED, "lea", true ], [ outcome.state, outcome.ended_by, outcome.ended_by_person ]
        assert_equal %w[a1 b1], outcome.commits.map(&:sha)
        assert_equal [ [ "project_7_bot_1", false ], [ "lea", true ] ], outcome.comments.map { |comment| [ comment.author, comment.person ] }
      end

      test "the review's check is a commit status under its own name" do
        GitlabApi.any_instance.expects(:post).with("#{PROJECT}/statuses/#{'a' * 40}", { "state" => "failed", "name" => Integrations::ReviewHost::CHECK_NAME,
                                                                                         "description" => "1 finding is open.", "target_url" => "https://firefight.test/x" }).returns({})
        check = Integrations::ReviewHost::Check.new(state: Integrations::ReviewHost::CHECK_FAILING, description: "1 finding is open.", url: "https://firefight.test/x")

        assert Integrations::ReviewHost.sets_checks?(@row.integration)
        @pack.set_review_check(@row, repository: "acme/platform/web", sha: "a" * 40, check: check)
      end

      private

      def call(tool, arguments)
        result = @pack.public_send(tool, environment_row: @row, arguments: arguments)
        result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end

      def stub_get(path, query = nil, answer = nil)
        query, answer = {}, query if answer.nil?
        GitlabApi.any_instance.stubs(:get).with(*[ path, (query unless query.empty?) ].compact).returns(answer)
        GitlabApi.any_instance.stubs(:get).with(path, query).returns(answer) if query.empty?
      end

      def stub_list(path, items, query: {})
        GitlabApi.any_instance.stubs(:list).with(path, query).returns([ items, false ])
        GitlabApi.any_instance.stubs(:list).with(path).returns([ items, false ]) if query.empty?
      end

      def deployment(id, environment, sha)
        { "id" => id, "environment" => { "name" => environment }, "sha" => sha, "ref" => "main", "user" => { "username" => "ana" },
          "deployable" => { "finished_at" => "2026-10-0#{id}T00:00:00Z" } }
      end
    end
  end
end
