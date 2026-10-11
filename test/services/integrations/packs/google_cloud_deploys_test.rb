require "test_helper"

module Integrations
  module Packs
    # Cloud Deploy delivery pipelines and their stages on the map, rollouts as run history with each phase's jobs as parts,
    # their logs, and the rollback and cancel changes, read in the shapes the Cloud Deploy API v1 documents.
    class GoogleCloudDeploysTest < ActiveSupport::TestCase
      LOCATION = "projects/acme-prod/locations/us-central1".freeze
      PIPELINE_ID = "#{LOCATION}/deliveryPipelines/web".freeze
      STAGE_ID = "#{PIPELINE_ID}/targets/prod".freeze
      RUN_ID = "#{LOCATION}/services/web".freeze
      KEY = { "type" => "service_account", "client_email" => "firefight@acme-prod.iam.gserviceaccount.com", "private_key" => "pem" }.to_json
      PIPELINE = {
        "name" => PIPELINE_ID, "uid" => "u1", "description" => "Web to staging and prod", "updateTime" => "2026-10-01T09:00:00Z",
        "serialPipeline" => { "stages" => [ { "targetId" => "staging", "profiles" => [ "staging" ] },
                                            { "targetId" => "prod", "strategy" => { "canary" => { "canaryDeployment" => { "percentages" => [ 25 ] } } } } ] },
        "condition" => { "pipelineReadyCondition" => { "status" => true }, "targetsPresentCondition" => { "status" => true } }
      }.freeze
      TARGETS = [
        { "name" => "#{LOCATION}/targets/staging", "targetId" => "staging", "run" => { "location" => LOCATION } },
        { "name" => "#{LOCATION}/targets/prod", "targetId" => "prod", "requireApproval" => true, "run" => { "location" => LOCATION } }
      ].freeze
      ROLLOUT = {
        "name" => "#{PIPELINE_ID}/releases/rel-7/rollouts/rel-7-to-prod-0001", "targetId" => "prod", "state" => "FAILED",
        "createTime" => "2026-10-06T10:00:00Z", "deployStartTime" => "2026-10-06T10:02:00Z", "deployEndTime" => "2026-10-06T10:09:00Z",
        "approvalState" => "APPROVED", "deployFailureCause" => "EXECUTION_FAILED", "failureReason" => "Deploy job failed",
        "phases" => [
          { "id" => "canary-25", "state" => "FAILED", "deploymentJobs" => {
            "deployJob" => { "id" => "deploy", "state" => "SUCCEEDED", "jobRun" => "#{PIPELINE_ID}/releases/rel-7/rollouts/rel-7-to-prod-0001/jobRuns/jr1" },
            "verifyJob" => { "id" => "verify", "state" => "FAILED", "jobRun" => "#{PIPELINE_ID}/releases/rel-7/rollouts/rel-7-to-prod-0001/jobRuns/jr2" }
          } },
          { "id" => "stable", "state" => "SKIPPED", "skipMessage" => "An earlier phase failed",
            "deploymentJobs" => { "deployJob" => { "id" => "deploy", "state" => "SKIPPED", "skipMessage" => "An earlier phase failed" } } }
        ]
      }.freeze
      JOB_RUNS = [
        { "name" => "#{PIPELINE_ID}/releases/rel-7/rollouts/rel-7-to-prod-0001/jobRuns/jr1", "phaseId" => "canary-25", "jobId" => "deploy",
          "state" => "SUCCEEDED", "startTime" => "2026-10-06T10:02:00Z", "endTime" => "2026-10-06T10:05:00Z",
          "deployJobRun" => { "build" => "projects/acme-prod/locations/us-central1/builds/b-111" } },
        { "name" => "#{PIPELINE_ID}/releases/rel-7/rollouts/rel-7-to-prod-0001/jobRuns/jr2", "phaseId" => "canary-25", "jobId" => "verify",
          "state" => "FAILED", "startTime" => "2026-10-06T10:05:10Z", "endTime" => "2026-10-06T10:09:00Z",
          "verifyJobRun" => { "build" => "projects/acme-prod/locations/us-central1/builds/b-222", "failureCause" => "EXECUTION_FAILED",
                              "failureMessage" => "smoke test returned 503" } }
      ].freeze
      EARLIER = {
        "name" => "#{PIPELINE_ID}/releases/rel-6/rollouts/rel-6-to-prod-0001", "targetId" => "prod", "state" => "SUCCEEDED",
        "createTime" => "2026-10-05T10:00:00Z", "deployStartTime" => "2026-10-05T10:01:00Z", "deployEndTime" => "2026-10-05T10:06:00Z"
      }.freeze
      STAGING = {
        "name" => "#{PIPELINE_ID}/releases/rel-7/rollouts/rel-7-to-staging-0001", "targetId" => "staging", "state" => "SUCCEEDED",
        "createTime" => "2026-10-06T09:00:00Z", "deployStartTime" => "2026-10-06T09:00:30Z", "deployEndTime" => "2026-10-06T09:03:30Z"
      }.freeze
      RELEASES = [ { "name" => "#{PIPELINE_ID}/releases/rel-6", "createTime" => "2026-10-05T09:00:00Z" },
                   { "name" => "#{PIPELINE_ID}/releases/rel-7", "createTime" => "2026-10-06T08:59:00Z" } ].freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud")
        @row = @integration.integration_environments.create!
        GoogleCloud.store_credentials!(@row, GoogleCloud::KEY => KEY)
        @row.store_fields!(GoogleCloud::PROJECT => "acme-prod")
        @pack = GoogleCloud.new(@integration)
        service = { "name" => RUN_ID, "uri" => "https://web-abc-uc.a.run.app", "terminalCondition" => { "state" => "CONDITION_SUCCEEDED" },
                    "labels" => { "deploy.cloud.google.com/delivery-pipeline-id" => "web", "deploy.cloud.google.com/target-id" => "prod",
                                  "deploy.cloud.google.com/location" => "us-central1", "deploy.cloud.google.com/project-id" => "acme-prod",
                                  "deploy.cloud.google.com/release-id" => "rel-7" } }
        GoogleCloudApi.any_instance.stubs(:run_locations).returns(pages([ { "locationId" => "us-central1" } ]))
        GoogleCloudApi.any_instance.stubs(:run_services).returns(pages([ service ]))
        GoogleCloudApi.any_instance.stubs(:run_jobs).returns(pages([]))
        GoogleCloudApi.any_instance.stubs(:sql_instances).returns(pages([]))
        GoogleCloudApi.any_instance.stubs(:compute_instances).returns(GoogleCloudApi::Reached.new(items: [], complete: true, unreachable: []))
        GoogleCloudApi.any_instance.stubs(:clusters).returns(GoogleCloudApi::Reached.new(items: [], complete: true, unreachable: []))
        GoogleCloudApi.any_instance.stubs(:deploy_locations).returns(pages([ { "locationId" => "us-central1" }, { "locationId" => "europe-west1" } ]))
        GoogleCloudApi.any_instance.stubs(:delivery_pipelines).with("acme-prod", "us-central1").returns(pages([ PIPELINE ]))
        GoogleCloudApi.any_instance.stubs(:delivery_pipelines).with("acme-prod", "europe-west1").returns(pages([]))
        GoogleCloudApi.any_instance.stubs(:deploy_targets).returns(pages(TARGETS))
        GoogleCloudApi.any_instance.stubs(:delivery_pipeline).returns(PIPELINE)
      end

      test "a pipeline and each of its stages go on the map in order, each stage part of it, and what it released links to the stage" do
        GoogleCloudApi.any_instance.expects(:deploy_targets).with("acme-prod", "europe-west1").never

        snapshot = @pack.map_of(@row)

        pipeline = found(snapshot, PIPELINE_ID)
        assert_equal [ ResourceMap::KIND_PIPELINE, "web", "ready" ], [ pipeline.kind, pipeline.name, pipeline.status ]
        assert_equal "https://console.cloud.google.com/deploy/delivery-pipelines?project=acme-prod", pipeline.url
        assert_equal "staging, prod", pipeline.details["stages"]
        stage = found(snapshot, STAGE_ID)
        assert_equal [ ResourceMap::KIND_RELEASE_FLOW, "web prod" ], [ stage.kind, stage.name ]
        assert_equal({ "type" => "Cloud Deploy stage", "region" => "us-central1", "target" => "prod", "stage" => "2 of 2", "releases_to" => "Cloud Run in us-central1",
                       "requires_approval" => true, "strategy" => "canary" }, stage.details)
        links = snapshot.links.map { |link| [ link.from.last, link.to.last, link.relation ] }
        assert_includes links, [ STAGE_ID, PIPELINE_ID, ResourceMap::RELATION_PART_OF ]
        assert_includes links, [ RUN_ID, STAGE_ID, ResourceMap::RELATION_RELEASED_BY ]
        assert_equal 1, links.count { |_, _, relation| relation == ResourceMap::RELATION_RELEASED_BY }, "only what names its stage is linked"
        assert_empty snapshot.gaps
      end

      test "a project that never turned Cloud Deploy on has no pipelines rather than a gap, and a refusal is a gap naming both kinds" do
        GoogleCloudApi.any_instance.stubs(:deploy_locations).raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Cloud Deploy API has not been used in project 42 before or it is disabled")
        assert_empty @pack.map_of(@row).gaps

        GoogleCloudApi.any_instance.stubs(:deploy_locations).raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Permission denied")
        assert_equal [ [ ResourceMap::KIND_PIPELINE, ResourceMap::KIND_RELEASE_FLOW ] ], GoogleCloud.new(@integration).map_of(@row).gaps.map(&:kinds)
      end

      test "a stage's rollouts are run history, newest first, named by the stage, with the release and why one failed" do
        GoogleCloudApi.any_instance.expects(:releases).with("acme-prod", "us-central1", "web", page_size: 30).returns(RELEASES)
        GoogleCloudApi.any_instance.stubs(:rollouts).with("acme-prod", "us-central1", "web", "rel-7").returns([ STAGING, ROLLOUT ])
        GoogleCloudApi.any_instance.stubs(:rollouts).with("acme-prod", "us-central1", "web", "rel-6").returns([ EARLIER ])

        result = call("list_rollouts", "resource" => "web prod")

        runs = Capabilities::History.runs_of(result)
        assert_equal %w[rel-7/rel-7-to-prod-0001 rel-6/rel-6-to-prod-0001], runs.map(&:id)
        assert_equal [ Capabilities::History::FAILED, Capabilities::History::SUCCEEDED ], runs.map(&:status)
        assert_equal [ "web prod" ], runs.map(&:name).uniq
        assert_equal "release rel-7, Deploy job failed, execution failed", runs.first.detail
        assert_equal 420, runs.first.seconds
      end

      test "a pipeline's rollouts take in every stage, and a name keeps one stage's" do
        GoogleCloudApi.any_instance.stubs(:releases).returns(RELEASES)
        GoogleCloudApi.any_instance.stubs(:rollouts).with("acme-prod", "us-central1", "web", "rel-7").returns([ STAGING, ROLLOUT ])
        GoogleCloudApi.any_instance.stubs(:rollouts).with("acme-prod", "us-central1", "web", "rel-6").returns([ EARLIER ])

        assert_equal [ "web prod", "web staging", "web prod" ], Capabilities::History.runs_of(call("list_rollouts", "resource" => PIPELINE_ID)).map(&:name)
        assert_equal 1, Capabilities::History.runs_of(call("list_rollouts", "resource" => PIPELINE_ID, "name" => "staging")).size
      end

      test "a rollout named by its release and id is read with each phase's jobs, why one failed and a handle to its build's log" do
        GoogleCloudApi.any_instance.expects(:rollout).with("acme-prod", "us-central1", "web", "rel-7", "rel-7-to-prod-0001").returns(ROLLOUT)
        GoogleCloudApi.any_instance.expects(:job_runs).with("acme-prod", "us-central1", "web", "rel-7", "rel-7-to-prod-0001").returns(JOB_RUNS)

        run = Capabilities::History.runs_of(call("list_rollouts", "resource" => STAGE_ID, "run" => "rel-7/rel-7-to-prod-0001")).sole

        assert_equal [ "canary-25 deploy", "canary-25 verify", "stable deploy" ], run.parts.map(&:name)
        assert_equal [ Capabilities::History::SUCCEEDED, Capabilities::History::FAILED, Capabilities::History::SUCCEEDED ], run.parts.map(&:status)
        failed = run.first_failed_part
        assert_equal "smoke test returned 503, execution failed", failed.detail
        assert_equal({ "resource" => STAGE_ID, "run" => "rel-7/rel-7-to-prod-0001/canary-25/verify",
                       "start" => "2026-10-06T10:05:10Z", "end" => "2026-10-06T10:09:00Z" }, failed.log[Capabilities::History::LOG_ARGUMENTS])
        assert_equal "skipped, An earlier phase failed", run.parts.last.detail
        assert_nil run.parts.last.log, "a job that never ran has no build to read"
      end

      test "a rollout to another stage, a rollout that is not there and a run in another form are refused in words" do
        GoogleCloudApi.any_instance.stubs(:rollout).returns(STAGING)
        assert_match "went to staging, not prod", assert_raises(NativePack::Error) { call("list_rollouts", "resource" => STAGE_ID, "run" => "rel-7/rel-7-to-staging-0001") }.message

        GoogleCloudApi.any_instance.stubs(:rollout).raises(GoogleCloudApi::NotFound, "Google Cloud answered 404: not found")
        assert_match "web has no rollout nope in release rel-7", assert_raises(NativePack::Error) { call("list_rollouts", "resource" => STAGE_ID, "run" => "rel-7/nope") }.message
        assert_match "release/rollout", assert_raises(NativePack::Error) { call("list_rollouts", "resource" => STAGE_ID, "run" => "just-one") }.message
      end

      test "a rollout's logs are what its jobs' builds printed, one job's alone when the run names it" do
        GoogleCloudApi.any_instance.stubs(:rollout).returns(ROLLOUT)
        GoogleCloudApi.any_instance.stubs(:job_runs).returns(JOB_RUNS)
        filter = nil
        GoogleCloudApi.any_instance.expects(:log_entries).with { |_project, asked, limit:| limit == 200 && (filter = asked) }.returns([])

        call("search_logs", "resource" => "web prod", "run" => "rel-7/rel-7-to-prod-0001/canary-25/verify")

        assert_equal 'resource.type="build" AND (resource.labels.build_id="b-222") AND timestamp>="2026-10-06T10:01:00Z" AND timestamp<="2026-10-06T10:10:00Z"', filter
      end

      test "a stage rolls back to the release named, says what ran before, and keeps every guard" do
        GoogleCloudApi.any_instance.stubs(:release).returns({ "name" => "#{PIPELINE_ID}/releases/rel-6" })
        GoogleCloudApi.any_instance.stubs(:releases).returns(RELEASES)
        GoogleCloudApi.any_instance.stubs(:rollouts).with("acme-prod", "us-central1", "web", "rel-7").returns([ ROLLOUT ])
        GoogleCloudApi.any_instance.stubs(:rollouts).with("acme-prod", "us-central1", "web", "rel-6").returns([ EARLIER ])
        sent = nil
        GoogleCloudApi.any_instance.expects(:rollback_target).with { |project, location, pipeline, body| [ project, location, pipeline ] == %w[acme-prod us-central1 web] && (sent = body) }
                      .returns("rollbackConfig" => { "rollout" => { "name" => "#{PIPELINE_ID}/releases/rel-6/rollouts/firefight-rollback-1" } })

        result = call("rollback_target", "resource" => "web prod", "release" => "rel-6")

        assert_equal [ "prod", "rel-6" ], sent.values_at("targetId", "releaseId")
        assert_match(/\Afirefight-rollback-\h{8}\z/, sent["rolloutId"])
        assert_match "Cloud Deploy is rolling web prod back to rel-6", text(result)
        assert_match "Before, it ran release rel-7, so to undo, promote rel-7 to prod again.", text(result)

        assert_match "is a whole pipeline", assert_raises(NativePack::Error) { call("rollback_target", "resource" => PIPELINE_ID) }.message
        GoogleCloudApi.any_instance.stubs(:release).raises(GoogleCloudApi::NotFound, "Google Cloud answered 404: not found")
        assert_match "no release called rel-0", assert_raises(NativePack::Error) { call("rollback_target", "resource" => STAGE_ID, "release" => "rel-0") }.message
        GoogleCloudApi.any_instance.stubs(:delivery_pipeline).returns(PIPELINE.merge("suspended" => true))
        assert_match "suspended", assert_raises(NativePack::Error) { call("rollback_target", "resource" => STAGE_ID) }.message
      end

      test "a rollout still going is cancelled, and one that ended is refused" do
        GoogleCloudApi.any_instance.stubs(:rollout).returns(ROLLOUT.merge("state" => "PENDING_APPROVAL"))
        GoogleCloudApi.any_instance.expects(:cancel_rollout).with("acme-prod", "us-central1", "web", "rel-7", "rel-7-to-prod-0001").returns({})

        assert_match "Cloud Deploy is cancelling rollout rel-7-to-prod-0001 of release rel-7 to prod", text(call("cancel_rollout", "resource" => STAGE_ID, "run" => "rel-7/rel-7-to-prod-0001"))

        GoogleCloudApi.any_instance.stubs(:rollout).returns(ROLLOUT)
        assert_match "has already ended (failed)", assert_raises(NativePack::Error) { call("cancel_rollout", "resource" => STAGE_ID, "run" => "rel-7/rel-7-to-prod-0001") }.message
        assert_includes IntegrationProvider.find("google_cloud").stopping_tools, "cancel_rollout"
      end

      test "a pipeline's details list its stages in order, where each releases to and which need an approval" do
        shown = text(call("describe_resource", "resource" => STAGE_ID))

        assert_match "web, a Cloud Deploy delivery pipeline in us-central1", shown
        assert_match "- staging, Cloud Run in us-central1", shown
        assert_match "- prod, Cloud Run in us-central1, needs an approval, canary strategy", shown
        assert_match "This is stage prod.", shown
      end

      test "a re-read of a pipeline reads its stages again, a stage it dropped is gone, and a pipeline Google no longer has goes with its stages" do
        ResourceMap.record!(@row, @pack.map_of(@row))
        GoogleCloudApi.any_instance.stubs(:delivery_pipeline).returns(PIPELINE.deep_merge("serialPipeline" => { "stages" => [ { "targetId" => "staging" } ] }))
        scope = ResourceMap::Scope.new(account: "acme-prod", kind: ResourceMap::KIND_PIPELINE, external_id: PIPELINE_ID)

        refreshed = @pack.map_refresh(@row, scope)

        assert_equal [ PIPELINE_ID, "#{PIPELINE_ID}/targets/staging" ], refreshed.resources.map(&:external_id)
        assert_equal [ [ "google_cloud", "acme-prod", ResourceMap::KIND_RELEASE_FLOW, STAGE_ID ] ], refreshed.gone

        GoogleCloudApi.any_instance.stubs(:delivery_pipeline).raises(GoogleCloudApi::NotFound, "Google Cloud answered 404: not found")
        gone = @pack.map_refresh(@row, ResourceMap::Scope.new(account: "acme-prod", kind: ResourceMap::KIND_RELEASE_FLOW, external_id: STAGE_ID)).gone
        assert_equal [ PIPELINE_ID, "#{PIPELINE_ID}/targets/staging", STAGE_ID ].sort, gone.map(&:last).sort
      end

      private

      def found(snapshot, id) = snapshot.resources.find { |resource| resource.external_id == id }

      def pages(items, complete: true) = Integrations::Pages::Read.new(items: items, complete: complete)

      def call(tool, arguments = {}) = @pack.call(tool, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
