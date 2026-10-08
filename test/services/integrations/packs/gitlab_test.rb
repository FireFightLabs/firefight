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
        assert_equal %w[run_tests retry_pipeline run_pipeline cancel_pipeline], Gitlab.tool_definitions.reject(&:read_only).map(&:name),
                     "only the sandbox's test runner and the pipeline changes write, so they arrive switched off"
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

        text = call(:recent_deployments, "repo" => "acme/platform/web", "deployment_environment" => "production", "limit" => 2)

        assert_equal "2026-10-01T10:00:00Z  production  main  #{'a' * 12}  success  by ana  deployment 9  job 77 https://gitlab.com/acme/platform/web/-/jobs/77", text
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
        stub_get("#{PROJECT}/pipelines", { "ref" => nil, "per_page" => 50 }, [
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

      test "a pipeline without a name is called by its branch" do
        stub_get("#{PROJECT}/pipelines", { "ref" => nil, "per_page" => 10 }, [ { "id" => 31, "status" => "failed", "ref" => "main" } ])
        stub_get("#{PROJECT}/pipelines/31", { "id" => 31, "status" => "failed", "ref" => "main", "created_at" => "2026-10-01T10:00:00Z" })

        run = Capabilities::History.runs_of(@pack.ci_runs(environment_row: @row, arguments: { "repo" => "acme/platform/web" })).sole

        assert_equal [ "pipeline on main", "failed" ], [ run.name, run.status ]
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
