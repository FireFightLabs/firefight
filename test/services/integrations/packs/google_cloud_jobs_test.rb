require "test_helper"

module Integrations
  module Packs
    # Cloud Run jobs on the map, their executions as run history with each task a part, and their logs per run, read in the
    # shapes Cloud Run Admin API v2 documents (Job, Execution, Task, Condition).
    class GoogleCloudJobsTest < ActiveSupport::TestCase
      JOB_ID = "projects/acme-prod/locations/us-central1/jobs/nightly".freeze
      KEY = { "type" => "service_account", "client_email" => "firefight@acme-prod.iam.gserviceaccount.com", "private_key" => "pem" }.to_json
      JOB = {
        "name" => JOB_ID, "labels" => { "team" => "data" }, "executionCount" => 42, "updateTime" => "2026-10-06T08:00:00Z", "lastModifier" => "ana@acme.dev",
        "terminalCondition" => { "type" => "Ready", "state" => "CONDITION_SUCCEEDED" },
        "latestCreatedExecution" => { "name" => "#{JOB_ID}/executions/nightly-x2k9p", "createTime" => "2026-10-06T02:00:00Z", "completionStatus" => "EXECUTION_FAILED" },
        "template" => { "taskCount" => 2, "parallelism" => 2,
                        "template" => { "maxRetries" => 1, "timeout" => "600s",
                                        "containers" => [ { "image" => "us-docker.pkg.dev/acme/etl:v9", "env" => [ { "name" => "DATABASE_URL", "valueSource" => { "secretKeyRef" => { "secret" => "db", "version" => "latest" } } } ] } ],
                                        "volumes" => [ { "name" => "db", "cloudSqlInstance" => { "instances" => [ "acme-prod:us-central1:orders" ] } } ] } }
      }.freeze
      FAILED = {
        "name" => "#{JOB_ID}/executions/nightly-x2k9p", "createTime" => "2026-10-06T02:00:00Z", "startTime" => "2026-10-06T02:00:05Z",
        "completionTime" => "2026-10-06T02:07:05Z", "taskCount" => 2, "succeededCount" => 1, "failedCount" => 1, "retriedCount" => 1,
        "logUri" => "https://console.cloud.google.com/logs/viewer?project=acme-prod&execution=nightly-x2k9p",
        "conditions" => [ { "type" => "Completed", "state" => "CONDITION_FAILED", "executionReason" => "NON_ZERO_EXIT_CODE", "message" => "Task nightly-x2k9p-task1 failed with exit code 1." } ]
      }.freeze
      DONE = {
        "name" => "#{JOB_ID}/executions/nightly-a1b2c", "createTime" => "2026-10-05T02:00:00Z", "startTime" => "2026-10-05T02:00:04Z",
        "completionTime" => "2026-10-05T02:05:04Z", "taskCount" => 2, "succeededCount" => 2,
        "conditions" => [ { "type" => "Completed", "state" => "CONDITION_SUCCEEDED" } ]
      }.freeze
      STOPPED = {
        "name" => "#{JOB_ID}/executions/nightly-s9s9s", "createTime" => "2026-10-04T02:00:00Z", "startTime" => "2026-10-04T02:00:04Z",
        "completionTime" => "2026-10-04T02:01:04Z", "taskCount" => 2, "cancelledCount" => 2,
        "conditions" => [ { "type" => "Completed", "state" => "CONDITION_FAILED", "executionReason" => "CANCELLED" } ]
      }.freeze
      TASKS = [
        { "name" => "#{JOB_ID}/executions/nightly-x2k9p/tasks/nightly-x2k9p-task1", "index" => 1, "startTime" => "2026-10-06T02:00:06Z",
          "completionTime" => "2026-10-06T02:07:00Z", "retried" => 1, "logUri" => "https://console.cloud.google.com/logs/viewer?task=1",
          "lastAttemptResult" => { "exitCode" => 1, "status" => { "code" => 2, "message" => "Container exited with code 1" } } },
        { "name" => "#{JOB_ID}/executions/nightly-x2k9p/tasks/nightly-x2k9p-task0", "index" => 0, "startTime" => "2026-10-06T02:00:06Z",
          "completionTime" => "2026-10-06T02:04:00Z", "lastAttemptResult" => { "exitCode" => 0, "status" => { "code" => 0 } } }
      ].freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud")
        @row = @integration.integration_environments.create!
        GoogleCloud.store_credentials!(@row, GoogleCloud::KEY => KEY)
        @row.store_fields!(GoogleCloud::PROJECT => "acme-prod")
        @pack = GoogleCloud.new(@integration)
        GoogleCloudApi.any_instance.stubs(:run_locations).returns(pages([ { "locationId" => "us-central1" } ]))
        GoogleCloudApi.any_instance.stubs(:run_services).returns(pages([]))
        GoogleCloudApi.any_instance.stubs(:run_jobs).returns(pages([ JOB ]))
        GoogleCloudApi.any_instance.stubs(:sql_instances).returns(pages([]))
        GoogleCloudApi.any_instance.stubs(:compute_instances).returns(GoogleCloudApi::Reached.new(items: [], complete: true, unreachable: []))
        GoogleCloudApi.any_instance.stubs(:clusters).returns(GoogleCloudApi::Reached.new(items: [], complete: true, unreachable: []))
        GoogleCloudApi.any_instance.stubs(:deploy_locations).returns(pages([]))
      end

      test "a job goes on the map as its last execution ended, with its settings read in memory and the Cloud SQL instances it mounts" do
        snapshot = @pack.map_of(@row)

        job = snapshot.resources.find { |resource| resource.external_id == JOB_ID }
        assert_equal [ ResourceMap::KIND_JOB, "nightly", "failed" ], [ job.kind, job.name, job.status ]
        assert_equal "https://console.cloud.google.com/run/jobs?project=acme-prod", job.url
        assert_equal({ "type" => "Cloud Run job", "region" => "us-central1", "image" => "us-docker.pkg.dev/acme/etl:v9", "latest_execution" => "nightly-x2k9p",
                       ResourceMap::TAGS => { "team" => "data" } }, job.details)
        assert_includes snapshot.links.map { |link| [ link.from.last, link.to.last, link.relation ] }, [ JOB_ID, "acme-prod:us-central1:orders", ResourceMap::RELATION_USES ]
        assert_equal [ [ "DATABASE_URL", false ] ], snapshot.uses.map { |found| [ found.variable, found.address? ] }, "a value from Secret Manager is named only"
        assert_empty snapshot.gaps
      end

      test "executions are run history, newest first, with how their tasks went and how long finished ones usually take" do
        GoogleCloudApi.any_instance.expects(:job_executions).with("acme-prod", "us-central1", "nightly").returns(pages([ STOPPED, FAILED, DONE ]))

        result = call("list_executions", "resource" => "nightly")

        runs = Capabilities::History.runs_of(result)
        assert_equal %w[nightly-x2k9p nightly-a1b2c nightly-s9s9s], runs.map(&:id)
        assert_equal [ Capabilities::History::FAILED, Capabilities::History::SUCCEEDED, Capabilities::History::CANCELLED ], runs.map(&:status)
        assert_equal [ 420, 300 ], runs.first(2).map(&:seconds)
        assert_equal "1 of 2 tasks succeeded, 1 failed, 1 retried, Task nightly-x2k9p-task1 failed with exit code 1.", runs.first.detail
        assert_equal FAILED["logUri"], runs.first.url
        assert_equal "nightly", runs.first.name
        assert_match "Finished ones usually take 5 minutes", text(result)
        assert_nil runs.first.parts
      end

      test "an execution named by its id is read with each task as a part, its exit code and a handle to its own lines" do
        GoogleCloudApi.any_instance.expects(:job_execution).with("acme-prod", "us-central1", "nightly", "nightly-x2k9p").returns(FAILED)
        GoogleCloudApi.any_instance.expects(:execution_tasks).with("acme-prod", "us-central1", "nightly", "nightly-x2k9p").returns(pages(TASKS))

        run = Capabilities::History.runs_of(call("list_executions", "resource" => JOB_ID, "run" => "#{JOB_ID}/executions/nightly-x2k9p")).sole

        assert_equal [ "task 0", "task 1" ], run.parts.map(&:name)
        failed = run.first_failed_part
        assert_equal [ "task 1", "Container exited with code 1, exit code 1, retried 1 time" ], [ failed.name, failed.detail ]
        assert_equal "search_logs", failed.log[Capabilities::History::LOG_TOOL]
        assert_equal({ "resource" => JOB_ID, "run" => "nightly-x2k9p/1", "start" => "2026-10-06T02:00:06Z", "end" => "2026-10-06T02:07:00Z" },
                     failed.log[Capabilities::History::LOG_ARGUMENTS])
        assert_equal TASKS.first["logUri"], failed.url
      end

      test "an execution the job does not have is refused in words" do
        GoogleCloudApi.any_instance.stubs(:job_execution).raises(GoogleCloudApi::NotFound, "Google Cloud answered 404: not found")

        error = assert_raises(NativePack::Error) { call("list_executions", "resource" => JOB_ID, "run" => "nope") }
        assert_equal "nightly has no execution called nope. list_executions shows them.", error.message
      end

      test "a job's logs are read by its labels, narrowed to one execution and task over that execution's own time" do
        GoogleCloudApi.any_instance.stubs(:job_execution).returns(FAILED)
        filter = nil
        GoogleCloudApi.any_instance.expects(:log_entries).with { |project, asked, limit:| project == "acme-prod" && limit == 200 && (filter = asked) }
                      .returns([ { "timestamp" => "2026-10-06T02:06:59Z", "textPayload" => "KeyError: region", "resource" => { "labels" => { "job_name" => "nightly" } } } ])

        result = call("search_logs", "resource" => "nightly", "run" => "nightly-x2k9p/1", "text" => "Error")

        assert_equal 'resource.type="cloud_run_job" AND resource.labels.job_name="nightly" AND resource.labels.location="us-central1" AND ' \
                     'labels."run.googleapis.com/execution_name"="nightly-x2k9p" AND labels."run.googleapis.com/task_index"="1" AND ' \
                     'timestamp>="2026-10-06T01:59:05Z" AND timestamp<="2026-10-06T02:08:05Z" AND SEARCH("Error")', filter
        assert_match "KeyError: region", text(result)
        assert_match "execution nightly-x2k9p, task 1", text(result)
        assert_raises(NativePack::Error) { call("search_logs", "resource" => "nightly", "run" => "nightly-x2k9p/first") }
        assert_raises(NativePack::Error) { call("search_logs", "resource" => "nightly", "stream" => "requests") }
      end

      test "a job's details say how its last execution went and how its tasks run, and a job has no metrics or restart here" do
        GoogleCloudApi.any_instance.stubs(:run_job).returns(JOB)

        shown = text(call("describe_resource", "resource" => "nightly"))

        assert_match "nightly, a Cloud Run job, failed", shown
        assert_match "Last execution nightly-x2k9p", shown
        assert_match "2 tasks an execution, 2 at a time, each retried up to 1 times within 600s", shown
        assert_raises(NativePack::Error) { call("query_metrics", "resource" => "nightly") }
        assert_raises(NativePack::Error) { call("restart_resource", "resource" => "nightly") }
      end

      test "a re-read of one job reads it again, and a job Google no longer has is gone" do
        GoogleCloudApi.any_instance.stubs(:run_job).returns(JOB)
        scope = ResourceMap::Scope.new(account: "acme-prod", kind: ResourceMap::KIND_JOB, external_id: JOB_ID)

        assert_equal [ JOB_ID ], @pack.map_refresh(@row, scope).resources.map(&:external_id)

        GoogleCloudApi.any_instance.stubs(:run_job).raises(GoogleCloudApi::NotFound, "Google Cloud answered 404: not found")
        assert_equal [ [ "google_cloud", "acme-prod", ResourceMap::KIND_JOB, JOB_ID ] ], @pack.map_refresh(@row, scope).gone
      end

      private

      def pages(items, complete: true) = Integrations::Pages::Read.new(items: items, complete: complete)

      def call(tool, arguments = {}) = @pack.call(tool, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
