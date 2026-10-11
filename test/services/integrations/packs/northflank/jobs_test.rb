require "test_helper"

module Integrations
  module Packs
    class Northflank
      # A job read the way a service is: its logs (one run's alone), its metrics, how it is set up, its builds and their
      # logs, and its runs as run history. A database's backups are its run history.
      class JobsTest < ActiveSupport::TestCase
        History = Capabilities::History

        setup do
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
          @row = @integration.integration_environments.create!
          Northflank.store_credentials!(@row, Northflank::API_TOKEN => "nf-token")
          @row.store_fields!(Northflank::PROJECT => "firefight")
          @pack = Northflank.new(@integration)
          NorthflankApi.any_instance.stubs(:services).returns(listed([
            { "id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/firefight-labs/firefight/web" }
          ]))
          NorthflankApi.any_instance.stubs(:addons).returns(listed([
            { "id" => "db", "name" => "db", "spec" => { "type" => "postgresql" }, "status" => "running", "appId" => "/firefight-labs/firefight/db" }
          ]))
          NorthflankApi.any_instance.stubs(:jobs).returns(listed([
            { "id" => "nightly", "name" => "nightly-export", "jobType" => "cron", "appId" => "/firefight-labs/firefight/nightly" }
          ]))
        end

        test "a job's logs are read like a service's, and one run's alone when it is named" do
          NorthflankApi.any_instance.expects(:logs).with("firefight", "jobs", "nightly", has_entries("runId" => "run-77", "regexIncludes" => "error"))
                       .returns([ { "ts" => "2026-10-01T02:00:00Z", "log" => "error: disk full", "containerId" => "nightly-abc" } ])

          text = call(:search_logs, "resource" => "nightly-export", "run" => "run-77", "regex" => "error")

          assert_match "error: disk full", text
          assert_match %r{https://app\.northflank\.com/t/firefight-labs/project/firefight/jobs/nightly\z}, text
          assert_match "only a job has runs", assert_raises(NativePack::Error) { call(:search_logs, "resource" => "web", "run" => "run-77") }.message
        end

        test "a job's metrics, one run's when named, and its builds and their logs" do
          NorthflankApi.any_instance.expects(:metrics).with("firefight", "jobs", "nightly", has_entries("runId" => "run-77")).returns({})
          NorthflankApi.any_instance.expects(:builds).with("firefight", "nightly", limit: 10, kind: "jobs").returns([ { "id" => "lucky-cat-3", "status" => "FAILURE", "concluded" => true } ])
          NorthflankApi.any_instance.expects(:build_logs).with("firefight", "nightly", has_entries("buildId" => "lucky-cat-3"), kind: "jobs")
                       .returns([ { "ts" => "2026-10-01T02:00:00Z", "log" => "npm ERR! missing script" } ])

          call(:query_metrics, "resource" => "nightly", "run" => "run-77")
          assert_match "build lucky-cat-3", call(:recent_builds, "resource" => "nightly")
          assert_match "npm ERR! missing script", call(:build_logs, "resource" => "nightly", "build" => "lucky-cat-3")
          assert_match "only services and jobs have builds", assert_raises(NativePack::Error) { call(:build_logs, "resource" => "db") }.message
        end

        test "a job is described with its schedule, retries, time limit, plan and latest runs" do
          NorthflankApi.any_instance.stubs(:job).with("firefight", "nightly").returns(
            "jobType" => "cron", "suspended" => true, "billing" => { "deploymentPlan" => "nf-compute-20" },
            "settings" => { "cron" => { "schedule" => "0 2 * * *", "concurrencyPolicy" => "Forbid" }, "backoffLimit" => 2, "activeDeadlineSeconds" => 3600 },
            "vcsData" => { "projectUrl" => "https://github.com/acme/app", "projectBranch" => "main" }
          )
          NorthflankApi.any_instance.stubs(:job_runs).with("firefight", "nightly", limit: 3).returns([ { "startedAt" => "2026-10-01T02:00:00Z", "status" => "FAILED" } ])

          text = call(:describe_resource, "resource" => "nightly")

          assert_match "nightly-export, cron job, suspended, so it does not run", text
          assert_match "Schedule: 0 2 * * * (UTC), when a run is still going: Forbid", text
          assert_match "Retries: 2, time limit 3600 seconds, plan nf-compute-20", text
          assert_match "Latest runs: 2026-10-01T02:00:00Z failed", text
        end

        test "a job's runs are its run history beside the same text, and one run is read by its id" do
          NorthflankApi.any_instance.stubs(:job_runs).with("firefight", "nightly", limit: 20).returns([
            { "id" => "run-78", "status" => "RUNNING", "startedAt" => "2026-10-02T02:00:00Z", "concluded" => false },
            { "id" => "run-77", "status" => "FAILED", "startedAt" => "2026-10-01T02:00:00Z", "concludedAt" => "2026-10-01T02:30:00Z", "concluded" => true, "failed" => 3 }
          ])
          NorthflankApi.any_instance.stubs(:job_run).with("firefight", "nightly", "run-12").returns(
            "id" => "run-12", "status" => "SUCCESS", "startedAt" => "2026-09-01T02:00:00Z", "concludedAt" => "2026-09-01T02:10:00Z", "concluded" => true
          )

          result = @pack.call("job_runs", environment_row: @row, arguments: { "job" => "nightly" })
          runs = History.runs_of(result)

          assert_match "2026-10-01T02:00:00Z, failed, finished 2026-10-01T02:30:00Z, 3 failed attempts, run run-77", result["content"].sole["text"]
          assert_equal [ [ "run-78", "running", nil ], [ "run-77", "failed", 1800 ] ], runs.map { |run| [ run.id, run.status, run.seconds ] }
          assert_equal "3 failed attempts", runs.last.detail
          one = History.runs_of(@pack.call("job_runs", environment_row: @row, arguments: { "job" => "nightly", "run" => "run-12" })).sole
          assert_equal [ "run-12", "succeeded", 600 ], [ one.id, one.status, one.seconds ]
        end

        test "a build is read by its id however old, with its own page" do
          NorthflankApi.any_instance.stubs(:build).with("firefight", "services", "web", "old-build-1").returns(
            "id" => "old-build-1", "status" => "SUCCESS", "createdAt" => "2026-08-01T10:00:00.000Z", "buildConcludedAt" => Time.utc(2026, 8, 1, 10, 5).to_i
          )

          run = History.runs_of(@pack.call("build_history", environment_row: @row, arguments: { "resource" => "web", "run" => "old-build-1" })).sole

          assert_equal [ "old-build-1", "succeeded", 300 ], [ run.id, run.status, run.seconds ]
          assert_equal "https://app.northflank.com/t/firefight-labs/project/firefight/services/web/builds/old-build-1", run.url
        end

        test "a database's backups are its run history, and only a database has them" do
          NorthflankApi.any_instance.stubs(:backups).with("firefight", "db", limit: 20).returns([
            { "id" => "b2", "name" => "nightly", "status" => "in-progress", "createdAt" => "2026-10-02T03:00:00Z" },
            { "id" => "b1", "name" => "nightly", "status" => "completed", "createdAt" => "2026-10-01T03:00:00Z", "completedAt" => "2026-10-01T03:12:00Z" }
          ])

          result = @pack.call("backup_history", environment_row: @row, arguments: { "resource" => "db" })

          assert_equal [ [ "b2", "running" ], [ "b1", "succeeded" ] ], History.runs_of(result).map { |run| [ run.id, run.status ] }
          assert_equal 12 * 60, result.dig(Telemetry::STRUCTURED, History::USUAL_SECONDS)
          assert_match "only databases have backups", assert_raises(NativePack::Error) { call(:backup_history, "resource" => "web") }.message
        end

        private

        def listed(items) = Pages::Read.new(items: items, complete: true)

        def call(tool, arguments) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
