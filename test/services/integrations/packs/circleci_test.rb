require "test_helper"

module Integrations
  module Packs
    class CircleciTest < ActiveSupport::TestCase
      ORG = { "id" => "org-1", "name" => "acme", "slug" => "gh/acme", "vcs-type" => "github" }.freeze
      APP_ORG = { "id" => "org-2", "name" => "beta", "slug" => "circleci/Ab12", "vcs-type" => "circleci" }.freeze
      WEB = { "id" => "p-1", "attributes" => { "name" => "web" } }.freeze
      API = { "id" => "p-2", "attributes" => { "name" => "api" } }.freeze
      SITE = "https://app.circleci.com".freeze
      RUN = {
        "id" => "r-9", "attributes" => {
          "number" => 41, "phase" => "ended", "current_outcome" => "failed", "created_at" => "2026-10-20T10:00:00Z",
          "workflows" => { "items" => [ { "id" => "w-1", "name" => "build", "phase" => "ended", "outcome" => "failed", "created_at" => "2026-10-20T10:00:05Z",
                                          "ended_at" => "2026-10-20T10:06:00Z" } ], "is_truncated" => false }
        },
        "references" => { "project" => { "id" => "p-1" }, "event" => { "attributes" => { "vcs" => { "branch" => "main", "revision" => "abcdef1234567890" } } } }
      }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Circleci::PROVIDER_KEY, name: "CircleCI")
        @row = @integration.integration_environments.create!
        Circleci.store_credentials!(@row, Circleci::API_TOKEN => " CCIPAT_x ")
        @pack = Circleci.new(@integration)
        CircleciApi.any_instance.stubs(:collaborations).returns([ ORG ])
        CircleciApi.any_instance.stubs(:projects).with("org-1").returns(Pages::Read.new(items: [ WEB ], complete: true))
        CircleciApi.any_instance.stubs(:project_by_slug).with("gh/acme/web").returns({ "vcs_info" => { "vcs_url" => "https://github.com/acme/web", "default_branch" => "main" } })
      end

      test "the token is stored trimmed, a wrong one is said on the form, and the changes are the ones that need a grant" do
        assert_equal "CCIPAT_x", @row.reload.credentials_hash[Circleci::API_TOKEN]
        assert_equal %w[approve_job cancel_workflow rerun_workflow rollback_deploy run_pipeline], Circleci.tool_definitions.reject(&:read_only).map(&:name).sort

        CircleciApi.any_instance.stubs(:me).raises(CircleciApi::Refused, "CircleCI answered 401: Invalid token provided.")
        assert_equal "CircleCI refused this token: CircleCI answered 401: Invalid token provided.", Circleci.credential_refusal({ Circleci::API_TOKEN => "bad" })
        assert_equal "Paste a personal API token.", Circleci.credential_refusal({})
      end

      test "each project goes on the map as a pipeline built from its repository, its slug read off a workflow when it is not written with names" do
        CircleciApi.any_instance.stubs(:collaborations).returns([ ORG, APP_ORG ])
        CircleciApi.any_instance.stubs(:projects).with("org-2").returns(Pages::Read.new(items: [ API ], complete: true))
        CircleciApi.any_instance.stubs(:project_by_slug).with("gh/acme/web").returns({ "vcs_info" => { "vcs_url" => "https://github.com/acme/web", "default_branch" => "main" } })
        CircleciApi.any_instance.stubs(:runs).with("p-2", limit: 1).returns([ { "id" => "r-1", "references" => { "event" => { "attributes" => { "vcs" => { "target_repository_url" => "https://gitlab.com/beta/api" } } } } } ])
        CircleciApi.any_instance.stubs(:workflows).with("r-1").returns([ { "id" => "w-7" } ])
        CircleciApi.any_instance.stubs(:workflow_summary).with("w-7").returns({ "project_slug" => "circleci/Ab12/Cd34" })
        CircleciApi.any_instance.stubs(:project_by_slug).with("circleci/Ab12/Cd34").returns({ "vcs_info" => {} })

        snapshot = @pack.map_of(@row)

        pipelines = snapshot.resources.select { |found| found.kind == ResourceMap::KIND_PIPELINE }.index_by(&:external_id)
        assert_equal [ "gh/acme/web", "#{SITE}/pipelines/github/acme/web", "main" ], [ pipelines["p-1"].name, pipelines["p-1"].url, pipelines["p-1"].details["branch"] ]
        assert_equal [ "circleci/Ab12/Cd34", "#{SITE}/pipelines/circleci/Ab12/Cd34" ], [ pipelines["p-2"].name, pipelines["p-2"].url ]
        repositories = snapshot.links.map { |link| [ link.from.last, link.to.values_at(0, 3), link.relation ] }
        assert_equal [ [ "p-1", %w[github acme/web], ResourceMap::RELATION_BUILT_FROM ], [ "p-2", %w[gitlab beta/api], ResourceMap::RELATION_BUILT_FROM ] ], repositories
        assert snapshot.complete?
      end

      test "a project list cut short is a gap, so nothing it did not read is taken as gone" do
        CircleciApi.any_instance.stubs(:projects).with("org-1").returns(Pages::Read.new(items: [ WEB ], complete: false))
        CircleciApi.any_instance.stubs(:project_by_slug).returns({})
        CircleciApi.any_instance.stubs(:runs).returns([])

        assert_includes @pack.map_of(@row).unread_kinds, ResourceMap::KIND_PIPELINE
      end

      test "a project's runs are its history, each linked to its workflow's page, and one run has every job as a part with its log" do
        CircleciApi.any_instance.stubs(:runs).with("p-1").returns([ RUN ])

        runs = Capabilities::History.runs_of(call(:ci_runs, "project" => "gh/acme/web"))

        run = runs.sole
        assert_equal [ "r-9", "41", "build", Capabilities::History::FAILED, 360 ], [ run.id, run.number, run.name, run.status, run.seconds ]
        assert_equal "#{SITE}/pipelines/github/acme/web", run.url

        CircleciApi.any_instance.stubs(:run).with("r-9").returns({ "data" => RUN })
        CircleciApi.any_instance.stubs(:workflows).with("r-9").returns([ { "id" => "w-1", "attributes" => RUN.dig("attributes", "workflows", "items").first } ])
        CircleciApi.any_instance.stubs(:workflow_summary).with("w-1").returns({ "project_slug" => "gh/acme/web", "pipeline_number" => 41 })
        CircleciApi.any_instance.stubs(:jobs).with("w-1").returns([
          { "id" => "j-1", "attributes" => { "name" => "test", "type" => "build", "phase" => "ended", "outcome" => "failed", "started_at" => "2026-10-20T10:01:00Z", "ended_at" => "2026-10-20T10:05:00Z" } },
          { "id" => "j-2", "attributes" => { "name" => "hold", "type" => "approval", "phase" => "blocked" } }
        ])

        one = Capabilities::History.runs_of(call(:ci_runs, "project" => "web", "run" => "r-9")).sole
        assert_equal "#{SITE}/pipelines/github/acme/web/41/workflows/w-1", one.url
        parts = one.parts
        assert_equal [ "build / test", Capabilities::History::FAILED, { "tool" => "get_job_logs", "arguments" => { "job" => "j-1" } } ], [ parts.first.name, parts.first.status, parts.first.log ]
        assert_nil parts.last.log, "an approval prints nothing"
      end

      test "a job's log is what its failed steps printed, filtered and cut, linked to its workflow" do
        CircleciApi.any_instance.stubs(:job).with("j-1").returns({ "data" => {
          "id" => "j-1", "attributes" => { "name" => "test", "phase" => "ended", "outcome" => "failed", "ended_at" => "2026-10-20T10:05:00Z",
                                           "parallel_executions" => [ { "steps" => [ { "name" => "checkout", "num" => 0, "outcome" => "succeeded", "exit_code" => 0 },
                                                                                     { "name" => "rspec", "num" => 101, "outcome" => "failed", "exit_code" => 1, "stderr_bytes" => 0 } ] } ] },
          "references" => { "workflow" => { "id" => "w-1" } }
        } })
        CircleciApi.any_instance.expects(:step_output).with("j-1", step: 101, execution: 0, stream: "stdout").returns("ok 1\nFailure: boom\nok 2\n")
        CircleciApi.any_instance.stubs(:workflow_summary).with("w-1").returns({ "project_slug" => "gh/acme/web", "pipeline_number" => 41 })

        text = call(:get_job_logs, "job" => "j-1", "text" => "boom")

        assert_match "Job test (j-1), ended, failed", text
        assert_match "Failure: boom", text
        assert_no_match(/ok 2/, text)
        assert text.end_with?("#{SITE}/pipelines/github/acme/web/41/workflows/w-1")
      end

      test "a held job is approved by its approval request, and a workflow holding none is refused" do
        CircleciApi.any_instance.stubs(:workflow_summary).returns({})
        CircleciApi.any_instance.stubs(:workflow_jobs).with("w-1").returns([ { "id" => "j-2", "name" => "hold", "type" => "approval", "status" => "on_hold", "approval_request_id" => "a-1" } ])
        CircleciApi.any_instance.expects(:approve).with("w-1", "a-1").returns({ "message" => "Accepted." })

        assert_match "Approved hold in workflow w-1", call(:approve_job, "workflow" => "w-1")

        CircleciApi.any_instance.stubs(:workflow_jobs).with("w-2").returns([])
        assert_raises(NativePack::Error) { call(:approve_job, "workflow" => "w-2") }
      end

      test "a workflow still going is not rerun, one that ended is not cancelled, and cancelling names who started it" do
        running = { "data" => { "id" => "w-1", "attributes" => { "name" => "build", "phase" => "started" } } }
        CircleciApi.any_instance.stubs(:workflow).with("w-1").returns(running)
        assert_raises(NativePack::Error) { call(:rerun_workflow, "workflow" => "w-1") }

        ended = { "data" => { "id" => "w-2", "attributes" => { "name" => "build", "phase" => "ended", "outcome" => "succeeded" } } }
        CircleciApi.any_instance.stubs(:workflow).with("w-2").returns(ended)
        assert_raises(NativePack::Error) { call(:cancel_workflow, "workflow" => "w-2") }
        assert_raises(NativePack::Error) { call(:rerun_workflow, "workflow" => "w-2", "from_failed" => true) }

        CircleciApi.any_instance.stubs(:workflow_summary).with("w-1").returns({ "name" => "build", "project_slug" => "gh/acme/web", "started_by" => "u-1" })
        CircleciApi.any_instance.stubs(:user).with("u-1").returns({ "login" => "ada", "name" => "Ada Lovelace" })
        owner = @pack.owner_of("cancel_workflow", environment_row: @row, arguments: { "workflow" => "w-1" })
        assert_equal [ "Ada Lovelace", Owner::ROLE_STARTED, "workflow build of gh/acme/web" ], [ owner.name, owner.role, owner.what ]
      end

      test "a pipeline runs on the default branch through the project's one pipeline, with its parameters" do
        CircleciApi.any_instance.stubs(:project_by_slug).with("gh/acme/web").returns({ "vcs_info" => { "default_branch" => "main", "vcs_url" => "https://github.com/acme/web" } })
        CircleciApi.any_instance.stubs(:pipelines).with("p-1").returns([ { "id" => "def-1" } ])
        CircleciApi.any_instance.stubs(:pipeline).with("def-1", "p-1").returns({ "data" => { "id" => "def-1", "attributes" => { "name" => "build-and-test" } } })
        CircleciApi.any_instance.expects(:start_run).with("def-1", "p-1", checkout: { "branch" => "main" }, config: { "branch" => "main" }, parameters: { "deploy" => true })
                   .returns({ "data" => { "id" => "r-10" } })

        assert_match "Started a run of build-and-test on main in gh/acme/web with deploy. It is run r-10.", call(:run_pipeline, "project" => "gh/acme/web", "parameters" => { "deploy" => true })
      end

      test "deploys are each component's versions with the live one, and a rollback goes from the live version to the one named" do
        CircleciApi.any_instance.stubs(:environments).with("org-1").returns([ { "id" => "e-1", "name" => "production" } ])
        CircleciApi.any_instance.stubs(:components).with("org-1", "p-1").returns([ { "id" => "c-1", "name" => "api" } ])
        CircleciApi.any_instance.stubs(:versions).with("c-1").returns([
          { "name" => "v42", "environment_id" => "e-1", "is_live" => true, "last_deployed_at" => "2026-10-20T09:00:00Z", "workflow_id" => "w-42" },
          { "name" => "v41", "environment_id" => "e-1", "is_live" => false, "last_deployed_at" => "2026-10-19T09:00:00Z", "workflow_id" => "w-41" }
        ])
        CircleciApi.any_instance.stubs(:project_by_slug).returns({})
        CircleciApi.any_instance.stubs(:runs).returns([])

        result = @pack.call("list_deploys", environment_row: @row, arguments: { "project" => "gh/acme/web" })
        deploys = Capabilities::Deploys.deploys_of(result)
        assert_equal [ [ "api/production/v42", true ], [ "api/production/v41", false ] ], deploys.map { |deploy| [ deploy.id, deploy.live ] }
        assert_equal "v42", Capabilities::Deploys.live(deploys).version

        CircleciApi.any_instance.expects(:rollback).with("p-1", { "component_name" => "api", "environment_name" => "production", "current_version" => "v42",
                                                                  "target_version" => "v41" }).returns({ "id" => "x-1", "rollback_type" => "pipeline" })
        text = call(:rollback_deploy, "project" => "web", "component" => "api", "environment" => "production", "version" => "v41")
        assert_match "from v42 to v41 (pipeline x-1). To undo it, rerun workflow w-42, which deployed v42.", text
        assert_raises(NativePack::Error) { call(:rollback_deploy, "project" => "web", "component" => "api", "environment" => "production", "version" => "v42") }
      end

      test "a component live in two namespaces of one environment is rolled back only in the one named, to a version deployed there" do
        CircleciApi.any_instance.stubs(:environments).with("org-1").returns([ { "id" => "e-1", "name" => "production" } ])
        CircleciApi.any_instance.stubs(:components).with("org-1", "p-1").returns([ { "id" => "c-1", "name" => "api" } ])
        CircleciApi.any_instance.stubs(:versions).with("c-1").returns([
          { "name" => "v42", "environment_id" => "e-1", "namespace" => "eu", "is_live" => true },
          { "name" => "v41", "environment_id" => "e-1", "namespace" => "eu", "is_live" => false },
          { "name" => "v40", "environment_id" => "e-1", "namespace" => "us", "is_live" => true }
        ])
        rollback = { "project" => "web", "component" => "api", "environment" => "production", "version" => "v41" }

        assert_match "Name one with namespace", assert_raises(NativePack::Error) { call(:rollback_deploy, rollback) }.message
        assert_raises(NativePack::Error) { call(:rollback_deploy, rollback.merge("namespace" => "us")) }
        CircleciApi.any_instance.expects(:rollback).with("p-1", has_entries("namespace" => "eu", "current_version" => "v42", "target_version" => "v41")).returns({ "id" => "x-2" })
        call(:rollback_deploy, rollback.merge("namespace" => "eu"))
      end

      test "the general read takes a versioned path, refuses a step's raw output, and keeps environment variables to their names" do
        CircleciApi.any_instance.expects(:read).with("/v2/project/gh/acme/web/envvar", {}).returns({ "items" => [ { "name" => "TOKEN", "value" => "xxxx1234" } ] })

        text = call(:api_read, "path" => "/v2/project/gh/acme/web/envvar")
        assert_match "TOKEN", text
        assert_no_match(/xxxx1234/, text)
        assert_raises(PolicyRefusal) { call(:api_read, "path" => "/v3/jobs/j-1/stdout") }
        assert_raises(NativePack::Error) { call(:api_read, "path" => "/me") }
      end

      private

      def call(tool, arguments)
        result = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)
        return result unless %i[get_job_logs approve_job run_pipeline rollback_deploy api_read].include?(tool)

        result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result.to_s
      end
    end
  end
end
