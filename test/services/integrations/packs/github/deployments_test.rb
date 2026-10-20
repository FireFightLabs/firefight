require "test_helper"

module Integrations
  module Packs
    class Github
      class DeploymentsTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "each deployment says its id, what it said, its log and where it serves, and is kept as a deploy and as a run" do
          GithubApp.stubs(:get).with("/repos/acme/web/deployments?environment=production&per_page=3", token: "ghs_token").returns([ deployment(5, "production") ])
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5/statuses?per_page=1", token: "ghs_token").returns([
            { "state" => "success", "created_at" => "2026-10-01T09:06:00Z", "description" => "Deployed.", "log_url" => "https://github.com/acme/web/actions/runs/41/job/9",
              "environment_url" => "https://web.example.com" }
          ])

          result = @pack.recent_deployments(environment_row: @row, arguments: { "repo" => "acme/web", "deployment_environment" => "production" })
          text = result["content"].first["text"]

          assert_includes text, "2026-10-01T09:00:00Z  production  main  success  by ana  deployment 5  Deployed  log https://github.com/acme/web/actions/runs/41/job/9  " \
                                "serves at https://web.example.com"
          assert text.end_with?("https://github.com/acme/web/deployments")
          assert_equal [ "5" ], Capabilities::Deploys.deploys_of(result).map(&:id)
          run = Capabilities::History.runs_of(result).sole
          assert_equal [ "deployment-5", Capabilities::History::SUCCEEDED, 360 ], [ run.id, run.status, run.seconds ]
        end

        test "a repository's environments say who must approve a deploy, how long it waits and which branches may deploy" do
          GithubApp.expects(:get).with("/repos/acme/web/environments?per_page=100", token: "ghs_token").returns("environments" => [
            { "name" => "production", "html_url" => "https://github.com/acme/web/deployments/activity_log?environments_filter=production",
              "deployment_branch_policy" => { "protected_branches" => true, "custom_branch_policies" => false },
              "protection_rules" => [
                { "type" => "required_reviewers", "prevent_self_review" => true,
                  "reviewers" => [ { "type" => "User", "reviewer" => { "login" => "ana" } }, { "type" => "Team", "reviewer" => { "slug" => "sre" } } ] },
                { "type" => "wait_timer", "wait_timer" => 30 }, { "type" => "branch_policy" }
              ] },
            { "name" => "staging", "html_url" => "https://github.com/acme/web/deployments/activity_log?environments_filter=staging", "protection_rules" => [] }
          ])

          text = @pack.list_environments(environment_row: @row, arguments: { "repo" => "acme/web" })["content"].first["text"]

          assert_includes text, "  production: needs approval from ana and the sre team, never by whoever started the deploy, waits 30 minutes before it deploys, " \
                                "only protected branches deploy  https://github.com/acme/web/deployments/activity_log?environments_filter=production"
          assert_includes text, "  staging: no rules, any branch deploys at once"
          assert Github.tool_definitions.find { |definition| definition.name == "list_environments" }.read_only
        end

        test "redeploying an earlier deployment runs again the job that made it, or its whole run when only the run is named" do
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5", token: "ghs_token").returns(deployment(5, "production"))
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5/statuses?per_page=100", token: "ghs_token")
                   .returns([ { "state" => "inactive", "log_url" => "https://github.com/acme/web/actions/runs/41/job/9" } ])
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41))
          GithubApp.stubs(:get).with("/repos/acme/web/actions/jobs/9", token: "ghs_token").returns("id" => 9, "run_id" => 41)
          GithubApp.expects(:act).with("/repos/acme/web/actions/jobs/9/rerun", {}, token: "ghs_token").returns({})

          text = @pack.redeploy(environment_row: @row, arguments: { "repo" => "acme/web", "deployment" => 5 })["content"].first["text"]

          assert_includes text, "Deploying the deployment 5 of #{'b' * 12} to production again, running the job that made it (job 9) and the jobs that depend on it in Deploy run 7 (41)"
          assert_not Github.tool_definitions.find { |definition| definition.name == "redeploy" }.read_only

          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5/statuses?per_page=100", token: "ghs_token")
                   .returns([ { "state" => "inactive" }, { "state" => "success", "target_url" => "https://github.com/acme/web/actions/runs/41" } ])
          GithubApp.expects(:act).with("/repos/acme/web/actions/runs/41/rerun", {}, token: "ghs_token").returns({})
          assert_includes @pack.redeploy(environment_row: @row, arguments: { "repo" => "acme/web", "deployment" => 5 })["content"].first["text"], "every job of the run that made it"
        end

        test "a run that built another commit, or a job of another run, is never run again for a deployment" do
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5", token: "ghs_token").returns(deployment(5, "production"))
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5/statuses?per_page=100", token: "ghs_token")
                   .returns([ { "state" => "success", "log_url" => "https://github.com/acme/web/actions/runs/41/job/9" } ])
          GithubApp.stubs(:get).with("/repos/acme/web/actions/jobs/9", token: "ghs_token").returns("id" => 9, "run_id" => 40)
          GithubApp.expects(:act).never

          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41).merge("head_sha" => "c" * 40))
          assert_match "which built #{'c' * 12} rather than #{'b' * 12}", assert_raises(Integrations::PolicyRefusal) {
            @pack.redeploy(environment_row: @row, arguments: { "repo" => "acme/web", "deployment" => 5 })
          }.message
          GithubApp.stubs(:get).with("/repos/acme/web/actions/runs/41", token: "ghs_token").returns(workflow_run(41))
          assert_match "job 9, which is not part of run 41", assert_raises(Integrations::PolicyRefusal) {
            @pack.redeploy(environment_row: @row, arguments: { "repo" => "acme/web", "deployment" => 5 })
          }.message
        end

        test "a deployment no GitHub Actions run made is refused, saying the system that made it deploys it again" do
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5", token: "ghs_token").returns(deployment(5, "web"))
          GithubApp.stubs(:get).with("/repos/acme/web/deployments/5/statuses?per_page=100", token: "ghs_token")
                   .returns([ { "state" => "success", "log_url" => "https://app.northflank.com/builds/1" } ])
          GithubApp.expects(:act).never

          error = assert_raises(Integrations::PolicyRefusal) { @pack.redeploy(environment_row: @row, arguments: { "repo" => "acme/web", "deployment" => 5 }) }

          assert_equal "The deployment 5 of #{'b' * 12} to web names no GitHub Actions run, so another system made it and Firefight cannot run it again. " \
                       "That system deploys #{'b' * 12} again.", error.message
        end

        private

        def deployment(id, environment)
          { "id" => id, "environment" => environment, "sha" => "b" * 40, "ref" => "main", "created_at" => "2026-10-01T09:00:00Z", "creator" => { "login" => "ana" } }
        end

        def workflow_run(id)
          { "id" => id, "name" => "Deploy", "run_number" => 7, "status" => "completed", "conclusion" => "success", "head_branch" => "main", "head_sha" => "b" * 40,
            "html_url" => "https://github.com/acme/web/actions/runs/#{id}" }
        end
      end
    end
  end
end
