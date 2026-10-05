require "test_helper"

module Integrations
  module Packs
    class Github
      class ActionsTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "the Actions tools only read, and recent deployments still reads three unless asked for more" do
          assert Github.tool_definitions.select { |definition| %w[workflow_runs workflow_jobs job_log ci_status].include?(definition.name) }.all?(&:read_only)
          GithubApp.expects(:get).with("/repos/acme/web/deployments?per_page=3", token: "ghs_token").returns([])
          @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/web" })
          GithubApp.expects(:get).with("/repos/acme/web/deployments?per_page=20", token: "ghs_token").returns([])
          @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/web", "limit" => 99 })
        end

        test "workflow runs are listed newest first, filtered as asked, each with its page" do
          GithubApp.expects(:get).with("/repos/acme/web/actions/runs?branch=main&per_page=5&status=failure", token: "ghs_token")
                   .returns("workflow_runs" => [ workflow_run(41, "CI", "failure") ])

          text = @pack.workflow_runs(environment_row: @row, arguments: { "repo" => "acme/web", "branch" => "main", "status" => "failure", "limit" => 5 })

          assert_equal "2026-10-01T09:00:00Z  run 41  CI #7  failure  main  #{'a' * 12}  push by ana  https://github.com/acme/web/actions/runs/41", text
          assert_match "status must be one of", assert_raises(NativePack::Error) { @pack.workflow_runs(environment_row: @row, arguments: { "repo" => "acme/web", "status" => "red" }) }.message
        end

        test "a run's jobs name the steps that failed, and link to the run" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41, "CI", "failure"))
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41/jobs?filter=latest&per_page=100", token: "ghs_token").returns("jobs" => [ job(9, "failure"), job(8, "success") ])

          text = text_of(@pack.workflow_jobs(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 41, "failed_only" => true }))

          assert_includes text, "CI run 7 (41) in acme/web, failure, on main at #{'a' * 12}."
          assert_includes text, "  test  failure at Run specs  65s  job 9  https://github.com/acme/web/actions/runs/41/job/9"
          assert_not_includes text, "job 8"
          assert text.end_with?("https://github.com/acme/web/actions/runs/41")
        end

        test "a job's log is the newest failed job's end, filtered as asked, with the steps that failed" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs?per_page=30&status=failure", token: "ghs_token").returns("workflow_runs" => [ workflow_run(41, "CI", "failure") ])
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41/jobs?filter=latest&per_page=100", token: "ghs_token").returns("jobs" => [ job(8, "success"), job(9, "failure") ])
          GithubApp.expects(:download).with("/repos/acme/web/actions/jobs/9/logs", token: "ghs_token")
                   .returns("2026-10-01T09:00:01Z ##[group]Run specs\n2026-10-01T09:00:02Z \e[31mFailure: pool exhausted\e[0m\n2026-10-01T09:00:03Z ##[error]Process completed with exit code 1.\n")

          text = text_of(@pack.job_log(environment_row: @row, arguments: { "repo" => "acme/web", "text" => "2026", "exclude" => "group" }))

          assert_includes text, "Job 9 CI / test in acme/web, failure, on main at #{'a' * 12}, finished 2026-10-01T09:02:05Z. Failed step: Run specs."
          assert_includes text, "Its log, 2 lines:\n2026-10-01T09:00:02Z Failure: pool exhausted\n2026-10-01T09:00:03Z ##[error]Process completed with exit code 1."
          assert text.end_with?("https://github.com/acme/web/actions/runs/41/job/9")
        end

        test "with no failed run in the time asked, the log says so" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs?branch=main&per_page=30&status=failure", token: "ghs_token").returns("workflow_runs" => [ workflow_run(41, "CI", "failure") ])

          text = @pack.job_log(environment_row: @row, arguments: { "repo" => "acme/web", "branch" => "main", "start" => "2026-09-01T00:00:00Z", "end" => "2026-09-02T00:00:00Z" })

          assert_equal "No failed GitHub Actions run in acme/web on main in that time among its newest 30 failed runs.", text
        end

        test "CI status puts the failing workflows first with their failed jobs, and says what each environment last received" do
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("default_branch" => "main")
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs?branch=main&per_page=30", token: "ghs_token").returns("workflow_runs" => [
            workflow_run(43, "Lint", "success", workflow: 2), workflow_run(42, "CI", "failure", workflow: 1), workflow_run(40, "CI", "success", workflow: 1)
          ])
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/42/jobs?filter=latest&per_page=100", token: "ghs_token").returns("jobs" => [ job(9, "failure") ])
          GithubApp.stubs(:get).with("/repos/acme/web/deployments?per_page=30", token: "ghs_token").returns([
            { "id" => 5, "environment" => "production", "sha" => "b" * 40, "ref" => "main", "created_at" => "t5", "creator" => { "login" => "ana" } },
            { "id" => 4, "environment" => "production", "sha" => "c" * 40 }
          ])
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5/statuses?per_page=1", token: "ghs_token").returns([ { "state" => "success" } ])

          text = text_of(@pack.ci_status(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "1 of 2 workflows fail on main. The latest run of each:\n  CI: failure, run 42"
          assert_includes text, "CI failed in:\n  test  failure at Run specs"
          assert_includes text, "Environments, what each last received:\n  production: #{'b' * 12} (main) at t5, success, by ana"
          assert_not_includes text, "c" * 12
          assert text.end_with?("https://github.com/acme/web/actions/runs/42")
        end

        test "a repository whose CI runs elsewhere is said to have no workflow runs" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs?branch=main&per_page=30", token: "ghs_token").returns("workflow_runs" => [])
          GithubApp.stubs(:get).with("/repos/acme/web/deployments?per_page=30", token: "ghs_token").returns([])

          assert_equal "No GitHub Actions workflow has run on main in acme/web. If its CI runs elsewhere, ask that connection.",
                       text_of(@pack.ci_status(environment_row: @row, arguments: { "repo" => "acme/web", "branch" => "main" }))
        end

        test "rerunning, starting and canceling a run are changes, so they arrive switched off and go through the gateway as writes" do
          changes = Github.tool_definitions.select { |definition| %w[rerun_workflow run_workflow cancel_workflow].include?(definition.name) }

          assert_equal 3, changes.size
          assert changes.none?(&:read_only)
        end

        test "a finished run runs again, only its failed jobs when asked, with its page and how to follow it" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41, "CI", "failure").merge("run_attempt" => 1))
          GithubApp.expects(:act).with("/repos/acme/web/actions/runs/41/rerun-failed-jobs", {}, token: "ghs_token").returns({})

          result = @pack.rerun_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 41, "failed_only" => true })

          assert_includes text_of(result), "CI run 7 (41) in acme/web runs again as attempt 2, its failed jobs and the jobs that depend on them, on main at #{'a' * 12}. " \
                                           "workflow_jobs with its run_id, or ci_status, follows it."
          assert text_of(result).end_with?("https://github.com/acme/web/actions/runs/41")

          GithubApp.expects(:act).with("/repos/acme/web/actions/runs/41/rerun", {}, token: "ghs_token").returns({})
          assert_includes text_of(@pack.rerun_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 41 })), "every job"
        end

        test "a run still going, or one that passed when only failed jobs are asked, is not run again" do
          GithubApp.expects(:act).never
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41, "CI", nil).merge("status" => "in_progress"))
          assert_equal "CI run 7 (41) in acme/web is still in_progress, so it cannot run again until it finishes. cancel_workflow stops it.",
                       assert_raises(NativePack::Error) { @pack.rerun_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 41 }) }.message

          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/42", token: "ghs_token").returns(workflow_run(42, "CI", "success"))
          assert_match "passed, so it has no failed jobs to run again",
                       assert_raises(NativePack::Error) { @pack.rerun_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 42, "failed_only" => true }) }.message
        end

        test "GitHub refusing for a missing permission is said with the permission to grant" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41, "CI", "failure"))
          GithubApp.stubs(:act).raises(GithubApp::NotPermitted, "GitHub answered 403: Resource not accessible by integration")

          error = assert_raises(NativePack::Error) { @pack.rerun_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 41 }) }

          assert_equal "GitHub refused to run acme/web run 41 again: GitHub answered 403: Resource not accessible by integration. Firefight's GitHub App " \
                       "needs the Actions: read and write permission on this installation for that. An owner of the GitHub account grants it under " \
                       "Settings, GitHub Apps, by accepting the App's new permissions.", error.message
        end

        test "a workflow is started by hand on a ref with the inputs it declares, and the run it started is linked" do
          stub_workflow(DISPATCHABLE)
          GithubApp.expects(:act).with("/repos/acme/web/actions/workflows/7/dispatches",
                                       { ref: "main", inputs: { "environment" => "staging", "dry_run" => "true" }, return_run_details: true }, token: "ghs_token")
                   .returns("workflow_run_id" => 99, "html_url" => "https://github.com/acme/web/actions/runs/99")

          result = @pack.run_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "workflow" => ".github/workflows/deploy.yml",
                                                                          "inputs" => { "environment" => "staging", "dry_run" => true } })

          assert_includes text_of(result), "Started Deploy (.github/workflows/deploy.yml) on main in acme/web with environment staging, dry_run true, as run 99. " \
                                           "workflow_jobs with its run_id, or ci_status, follows it."
          assert text_of(result).end_with?("https://github.com/acme/web/actions/runs/99")
        end

        test "a dispatch GitHub answers without the run's details says how to find it" do
          stub_workflow(DISPATCHABLE)
          GithubApp.stubs(:act).returns({})

          assert_equal "Started Deploy (.github/workflows/deploy.yml) on main in acme/web with environment production. GitHub did not say which run it is, " \
                       "so workflow_runs with event workflow_dispatch finds it.",
                       @pack.run_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "workflow" => "deploy.yml", "inputs" => { "environment" => "production" } })
        end

        test "a workflow without a workflow_dispatch trigger, or inputs it does not declare, is refused before anything is started" do
          GithubApp.expects(:act).never
          stub_workflow("name: Deploy\non:\n  push:\n    branches: [main]\n")
          assert_equal "Deploy (.github/workflows/deploy.yml) has no workflow_dispatch trigger on main, so it cannot be started by hand. It runs on the events it names.",
                       assert_raises(NativePack::Error) { run_deploy }.message

          stub_workflow(DISPATCHABLE)
          assert_equal "Deploy (.github/workflows/deploy.yml) declares no input region. It declares environment and dry_run.",
                       assert_raises(NativePack::Error) { run_deploy("environment" => "staging", "region" => "eu") }.message
          assert_equal "Deploy (.github/workflows/deploy.yml) needs input environment, which has no default.", assert_raises(NativePack::Error) { run_deploy }.message
          assert_equal "environment must be one of staging, production", assert_raises(NativePack::Error) { run_deploy("environment" => "dev") }.message
          assert_equal "dry_run must be true or false", assert_raises(NativePack::Error) { run_deploy("environment" => "staging", "dry_run" => "maybe") }.message
        end

        test "a bare on read as true by YAML, and a list of events, both name the trigger" do
          stub_workflow("name: Deploy\non: [push, workflow_dispatch]\n")
          GithubApp.expects(:act).with("/repos/acme/web/actions/workflows/7/dispatches", { ref: "main", return_run_details: true }, token: "ghs_token").returns({})

          assert_match "Started Deploy", run_deploy
        end

        test "a disabled workflow is not started" do
          GithubApp.expects(:act).never
          GithubApp.stubs(:get).with("/repos/acme/web/actions/workflows/deploy.yml", token: "ghs_token")
                   .returns("id" => 7, "name" => "Deploy", "path" => ".github/workflows/deploy.yml", "state" => "disabled_manually")

          assert_equal "Deploy (.github/workflows/deploy.yml) in acme/web is disabled manually, so it cannot be started. A person enables it in GitHub.",
                       assert_raises(NativePack::Error) { run_deploy }.message
        end

        test "a running run is canceled with its page, and a finished one is left as it is" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41, "Deploy", nil).merge("status" => "in_progress"))
          GithubApp.expects(:act).with("/repos/acme/web/actions/runs/41/cancel", token: "ghs_token").returns({})

          result = @pack.cancel_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 41 })

          assert_includes text_of(result), "Canceling Deploy run 7 (41) in acme/web on main at #{'a' * 12}."
          assert text_of(result).end_with?("https://github.com/acme/web/actions/runs/41")

          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/42", token: "ghs_token").returns(workflow_run(42, "Deploy", "success"))
          assert_equal "Deploy run 7 (42) in acme/web already finished, success, so there is nothing to cancel.",
                       assert_raises(NativePack::Error) { @pack.cancel_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 42 }) }.message
        end

        private

        DISPATCHABLE = <<~YAML.freeze
          name: Deploy
          on:
            workflow_dispatch:
              inputs:
                environment:
                  required: true
                  type: choice
                  options: [staging, production]
                dry_run:
                  type: boolean
                  default: false
        YAML

        def stub_workflow(file)
          GithubApp.stubs(:get).with("/repos/acme/web/actions/workflows/deploy.yml", token: "ghs_token")
                   .returns("id" => 7, "name" => "Deploy", "path" => ".github/workflows/deploy.yml", "state" => "active")
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("default_branch" => "main")
          GithubApp.stubs(:get).with("/repos/acme/web/contents/.github/workflows/deploy.yml?ref=main", token: "ghs_token").returns("content" => Base64.encode64(file))
        end

        def run_deploy(inputs = nil)
          @pack.run_workflow(environment_row: @row, arguments: { "repo" => "acme/web", "workflow" => "deploy.yml", "inputs" => inputs }.compact)
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result

        def workflow_run(id, name, conclusion, workflow: 1)
          { "id" => id, "name" => name, "run_number" => 7, "status" => "completed", "conclusion" => conclusion, "head_branch" => "main", "head_sha" => "a" * 40,
            "event" => "push", "actor" => { "login" => "ana" }, "created_at" => "2026-10-01T09:00:00Z", "updated_at" => "2026-10-01T09:05:00Z",
            "workflow_id" => workflow, "html_url" => "https://github.com/acme/web/actions/runs/#{id}" }
        end

        def job(id, conclusion)
          { "id" => id, "name" => "test", "workflow_name" => "CI", "conclusion" => conclusion, "status" => "completed", "head_branch" => "main", "head_sha" => "a" * 40,
            "started_at" => "2026-10-01T09:01:00Z", "completed_at" => "2026-10-01T09:02:05Z", "html_url" => "https://github.com/acme/web/actions/runs/41/job/#{id}",
            "steps" => [ { "name" => "Run specs", "conclusion" => conclusion } ] }
        end
      end
    end
  end
end
