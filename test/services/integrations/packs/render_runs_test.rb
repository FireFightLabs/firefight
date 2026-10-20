require "test_helper"

module Integrations
  module Packs
    # A cron job's runs, a service's one-off jobs and a workflow's task runs, each as run history.
    class RenderRunsTest < ActiveSupport::TestCase
      WEB_PAGE = "https://dashboard.render.com/web/srv-web".freeze
      CRON_PAGE = "https://dashboard.render.com/cron/crn-1".freeze
      WORKFLOW_PAGE = "https://dashboard.render.com/wf/wfl-1".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
        @row = @integration.integration_environments.create!
        Render.store_credentials!(@row, Render::API_KEY => "rnd_key")
        @row.store_fields!(Render::WORKSPACE => "tea-1")
        @pack = Render.new(@integration)
        RenderApi.any_instance.stubs(:services).with("tea-1").returns(listed([
          { "id" => "srv-web", "name" => "web", "type" => "web_service", "suspended" => "not_suspended", "dashboardUrl" => WEB_PAGE, "serviceDetails" => {} },
          { "id" => "crn-1", "name" => "nightly", "type" => "cron_job", "suspended" => "not_suspended", "dashboardUrl" => CRON_PAGE, "serviceDetails" => {} }
        ]))
        RenderApi.any_instance.stubs(:postgres_databases).with("tea-1").returns(listed([]))
        RenderApi.any_instance.stubs(:key_values).with("tea-1").returns(listed([]))
        RenderApi.any_instance.stubs(:workflows).with("tea-1").returns(listed([
          { "id" => "wfl-1", "name" => "mailer", "ownerId" => "tea-1", "region" => "oregon", "runCommand" => "python main.py",
            "buildConfig" => { "repo" => "https://github.com/acme/mailer", "branch" => "main", "runtime" => "python" } }
        ]))
        RenderApi.any_instance.stubs(:tasks).with("wfl-1").returns(listed([ { "id" => "tsk-1", "name" => "send_digest" }, { "id" => "tsk-2", "name" => "render_email" } ]))
      end

      test "a cron job's runs are paired from their start and end events, with why one failed and who started one by hand" do
        RenderApi.any_instance.expects(:events).with("crn-1", has_entries("type" => %w[cron_job_run_started cron_job_run_ended], "limit" => 100)).returns([
          { "timestamp" => "2026-10-02T03:00:01Z", "type" => "cron_job_run_started", "details" => { "cronJobRunId" => "crn-run-3" } },
          { "timestamp" => "2026-10-01T03:04:00Z", "type" => "cron_job_run_ended",
            "details" => { "cronJobRunId" => "crn-run-2", "status" => "unsuccessful", "reason" => { "evicted" => false, "nonZeroExit" => 2 } } },
          { "timestamp" => "2026-10-01T03:00:00Z", "type" => "cron_job_run_started", "details" => { "cronJobRunId" => "crn-run-2" } },
          { "timestamp" => "2026-09-30T03:02:00Z", "type" => "cron_job_run_ended",
            "details" => { "cronJobRunId" => "crn-run-1", "status" => "successful", "user" => { "id" => "usr-1", "email" => "ana@acme.dev" } } },
          { "timestamp" => "2026-09-30T03:00:00Z", "type" => "cron_job_run_started", "details" => { "cronJobRunId" => "crn-run-1" } },
          { "timestamp" => "2026-09-01T03:02:00Z", "type" => "cron_job_run_ended", "details" => { "cronJobRunId" => "crn-run-0", "status" => "successful" } }
        ])

        result = @pack.call("cron_runs", environment_row: @row, arguments: { "resource" => "nightly" })
        runs = Capabilities::History.runs_of(result)

        assert_equal [ [ "crn-run-3", "running" ], [ "crn-run-2", "failed" ], [ "crn-run-1", "succeeded" ] ], runs.map { |run| [ run.id, run.status ] }
        assert_equal "exited with code 2", runs.second.detail
        assert_equal 240, runs.second.seconds
        assert_equal "started by ana@acme.dev", runs.third.detail
        assert_equal CRON_PAGE, runs.first.url
      end

      test "one cron run has a part whose log is the cron job's over the time it ran, and a run not in the window is said" do
        RenderApi.any_instance.stubs(:events).returns([
          { "timestamp" => "2026-10-01T03:04:00Z", "type" => "cron_job_run_ended", "details" => { "cronJobRunId" => "crn-run-2", "status" => "unsuccessful" } },
          { "timestamp" => "2026-10-01T03:00:00Z", "type" => "cron_job_run_started", "details" => { "cronJobRunId" => "crn-run-2" } }
        ])

        run = Capabilities::History.runs_of(@pack.call("cron_runs", environment_row: @row, arguments: { "resource" => "nightly", "run" => "crn-run-2" })).sole

        assert_equal({ "tool" => "search_logs", "arguments" => { "resource" => "crn-1", "type" => "app", "start" => "2026-10-01T03:00:00Z", "end" => "2026-10-01T03:05:00Z" } },
                     run.parts.sole.log)
        assert_equal "run", run.first_failed_part.name
        assert_match "nightly had no run crn-run-9", assert_raises(NativePack::Error) { @pack.call("cron_runs", environment_row: @row, arguments: { "resource" => "nightly", "run" => "crn-run-9" }) }.message
        assert_match "only a cron job has scheduled runs", assert_raises(NativePack::Error) { @pack.call("cron_runs", environment_row: @row, arguments: { "resource" => "web" }) }.message
      end

      test "a service's one-off jobs are run history, and one job is read with why it failed and its own log" do
        RenderApi.any_instance.stubs(:jobs).with("srv-web", limit: 20).returns([
          { "id" => "job-2", "status" => "running", "startCommand" => "bin/rails db:migrate", "createdAt" => "2026-10-01T10:00:00Z", "startedAt" => "2026-10-01T10:00:05Z" },
          { "id" => "job-1", "status" => "succeeded", "startCommand" => "bin/rails data:backfill", "createdAt" => "2026-09-30T10:00:00Z",
            "startedAt" => "2026-09-30T10:00:10Z", "finishedAt" => "2026-09-30T10:05:10Z" }
        ])
        runs = Capabilities::History.runs_of(@pack.call("job_runs", environment_row: @row, arguments: { "resource" => "web" }))
        assert_equal [ [ "job-2", "running", "bin/rails db:migrate" ], [ "job-1", "succeeded", "bin/rails data:backfill" ] ], runs.map { |run| [ run.id, run.status, run.detail ] }
        assert_equal 300, runs.second.seconds

        RenderApi.any_instance.stubs(:job).with("srv-web", "job-3").returns(
          "id" => "job-3", "status" => "failed", "startCommand" => "bin/rails db:migrate", "createdAt" => "2026-10-01T11:00:00Z",
          "startedAt" => "2026-10-01T11:00:05Z", "finishedAt" => "2026-10-01T11:01:00Z"
        )
        RenderApi.any_instance.stubs(:events).with("srv-web", has_entries("type" => [ "job_run_ended" ])).returns([
          { "timestamp" => "2026-10-01T11:01:00Z", "type" => "job_run_ended", "details" => { "jobId" => "job-3", "status" => "failed", "reason" => { "evicted" => false, "oomKilled" => { "memoryLimit" => "512Mi" } } } }
        ])
        job = Capabilities::History.runs_of(@pack.call("job_runs", environment_row: @row, arguments: { "resource" => "web", "run" => "job-3" })).sole
        assert_equal "bin/rails db:migrate, ran out of memory, limit 512Mi", job.detail
        assert_equal({ "resource" => "srv-web", "job" => "job-3", "start" => "2026-10-01T11:00:05Z", "end" => "2026-10-01T11:02:00Z" }, job.parts.sole.log["arguments"])

        RenderApi.any_instance.expects(:logs).with(has_entries("resource" => "job-3", "startTime" => "2026-10-01T11:00:00Z", "endTime" => "2026-10-01T11:02:00Z"))
                 .returns("logs" => [ { "timestamp" => "2026-10-01T11:00:30Z", "message" => "PG::UndefinedTable" } ], "hasMore" => false)
        assert_match "PG::UndefinedTable", @pack.call("search_logs", environment_row: @row, arguments: { "resource" => "web", "job" => "job-3" })["content"].sole["text"]
      end

      test "a workflow's task runs are named by their task, and one is read with each attempt and the task runs it started" do
        RenderApi.any_instance.stubs(:task_runs).with("wfl-1", limit: 20).returns([
          { "id" => "trn-2", "taskId" => "tsk-2", "status" => "running", "startedAt" => "2026-10-01T10:00:02Z", "parentTaskRunId" => "trn-1", "rootTaskRunId" => "trn-1", "retries" => 0 },
          { "id" => "trn-1", "taskId" => "tsk-1", "status" => "failed", "startedAt" => "2026-10-01T10:00:00Z", "completedAt" => "2026-10-01T10:02:00Z",
            "rootTaskRunId" => "trn-1", "retries" => 2, "error" => "SMTP refused" }
        ])
        result = @pack.call("task_runs", environment_row: @row, arguments: { "resource" => "mailer", "name" => "send" })
        assert_equal [ [ "trn-1", "send_digest", "failed", "SMTP refused, retried 2 times" ] ],
                     Capabilities::History.runs_of(result).map { |run| [ run.id, run.name, run.status, run.detail ] }
        assert_includes result["content"].sole["text"], WORKFLOW_PAGE

        RenderApi.any_instance.stubs(:task_run).with("trn-1").returns(
          "id" => "trn-1", "taskId" => "tsk-1", "status" => "failed", "startedAt" => "2026-10-01T10:00:00Z", "completedAt" => "2026-10-01T10:02:00Z",
          "retries" => 1, "error" => "SMTP refused",
          "attempts" => [ { "attempt" => 0, "status" => "failed", "startedAt" => "2026-10-01T10:00:00Z", "completedAt" => "2026-10-01T10:01:00Z", "error" => "SMTP refused" },
                          { "attempt" => 1, "status" => "failed", "startedAt" => "2026-10-01T10:01:10Z", "completedAt" => "2026-10-01T10:02:00Z", "error" => "SMTP refused" } ]
        )
        RenderApi.any_instance.stubs(:child_task_runs).with("trn-1").returns([
          { "id" => "trn-1", "taskId" => "tsk-1", "status" => "failed" },
          { "id" => "trn-2", "taskId" => "tsk-2", "status" => "succeeded", "startedAt" => "2026-10-01T10:00:02Z", "completedAt" => "2026-10-01T10:00:09Z" }
        ])
        run = Capabilities::History.runs_of(@pack.call("task_runs", environment_row: @row, arguments: { "resource" => "mailer", "run" => "trn-1" })).sole
        assert_equal [ [ "attempt 1", "failed" ], [ "attempt 2", "failed" ], [ "render_email (task run trn-2)", "succeeded" ] ], run.parts.map { |part| [ part.name, part.status ] }
        assert_equal({ "resource" => "wfl-1", "task_run" => "trn-1", "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T10:02:00Z" }, run.parts.first.log["arguments"])
        assert_equal "trn-2", run.parts.last.log.dig("arguments", "task_run")

        RenderApi.any_instance.stubs(:task_run).with("trn-x").returns("id" => "trn-x", "taskId" => "tsk-other", "status" => "succeeded")
        assert_match "belongs to another workflow", assert_raises(NativePack::Error) { @pack.call("task_runs", environment_row: @row, arguments: { "resource" => "mailer", "run" => "trn-x" }) }.message
      end

      test "a workflow is listed, described, searched by task run and put on the map, and has no deploys" do
        assert_match "mailer (wfl-1), workflow", call(:list_resources)

        RenderApi.any_instance.stubs(:workflow).with("wfl-1").returns(
          "id" => "wfl-1", "name" => "mailer", "region" => "oregon", "runCommand" => "python main.py", "autoDeployTrigger" => "commit",
          "buildConfig" => { "repo" => "https://github.com/acme/mailer", "branch" => "main", "runtime" => "python" }
        )
        described = call(:describe_resource, "resource" => "mailer")
        assert_match "mailer, workflow, region oregon, runtime python", described
        assert_match "Tasks: send_digest, render_email", described

        RenderApi.any_instance.expects(:logs).with(has_entries("resource" => "wfl-1", "taskRun" => "trn-1")).returns("logs" => [], "hasMore" => false)
        call(:search_logs, "resource" => "mailer", "task_run" => "trn-1")
        assert_match "is not a workflow", assert_raises(NativePack::Error) { call(:search_logs, "resource" => "web", "task_run" => "trn-1") }.message
        assert_match "mailer is a workflow, and only services have deploys.", assert_raises(NativePack::Error) { call(:list_deployments, "resource" => "mailer") }.message

        RenderApi.any_instance.stubs(:deploys).returns([])
        RenderApi.any_instance.stubs(:custom_domains).returns(listed([]))
        RenderApi.any_instance.stubs(:env_vars).returns(listed([]))
        RenderApi.any_instance.stubs(:env_groups).returns([])
        found = @pack.map_of(@row).then { |snapshot| [ snapshot.resources.find { |each| each.external_id == "wfl-1" }, snapshot ] }
        assert_equal [ ResourceMap::KIND_WORKFLOW, WORKFLOW_PAGE ], [ found.first.kind, found.first.url ]
        assert_includes found.last.links.map { |link| [ link.from.last, link.relation, link.to.last ] }, [ "wfl-1", ResourceMap::RELATION_BUILT_FROM, "acme/mailer" ]
      end

      test "workflows Render refuses to list are said in the listing and are a gap on the map, holding back nothing else" do
        RenderApi.any_instance.stubs(:workflows).raises(RenderApi::Refused, "Render answered 403: workflows are not enabled")
        assert_match "Workflows could not be read: Render answered 403: workflows are not enabled.", call(:list_resources)

        RenderApi.any_instance.stubs(:deploys).returns([])
        RenderApi.any_instance.stubs(:custom_domains).returns(listed([]))
        RenderApi.any_instance.stubs(:env_vars).returns(listed([]))
        RenderApi.any_instance.stubs(:env_groups).returns([])
        assert_equal [ ResourceMap::KIND_WORKFLOW ], @pack.map_of(@row).unread_kinds
      end

      test "a service's status names the instances running now, and the plan's limits, instance count and bandwidth are metrics" do
        RenderApi.any_instance.stubs(:service).with("srv-web").returns("type" => "web_service", "serviceDetails" => { "numInstances" => 2 })
        RenderApi.any_instance.stubs(:deploys).returns([])
        RenderApi.any_instance.stubs(:events).returns([])
        RenderApi.any_instance.stubs(:instances).with("srv-web").returns([ { "id" => "srv-web-bbbbb", "createdAt" => "2026-10-01T11:00:00Z" },
                                                                           { "id" => "srv-web-aaaaa", "createdAt" => "2026-10-01T10:00:00Z" } ])
        assert_match "Instances running now, 2: srv-web-aaaaa since 2026-10-01T10:00:00Z, srv-web-bbbbb since 2026-10-01T11:00:00Z", call(:describe_resource, "resource" => "web")

        RenderApi.any_instance.expects(:metrics).with("bandwidth", Not(has_key("resolutionSeconds"))).returns([])
        RenderApi.any_instance.expects(:metrics).with("instance-count", has_key("resolutionSeconds")).returns([])
        RenderApi.any_instance.expects(:metrics).with("memory-limit", has_key("resolutionSeconds")).returns([])
        @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => %w[bandwidth instance_count memory_limit] })
        assert_match "Render does not keep replication_lag for a web service", call(:query_metrics, "resource" => "web", "metrics" => [ "replication_lag" ])
      end

      test "a cron job's run is started and cancelled at the cron job's runs, and only a cron job has them" do
        RenderApi.any_instance.expects(:trigger_cron_run).with("crn-1").returns("id" => "crn-run-9", "status" => "pending")
        assert_match "Render started run crn-run-9 of nightly, cancelling any run of it already going.", call(:trigger_cron_run, "resource" => "nightly")
        RenderApi.any_instance.stubs(:events).returns([
          { "timestamp" => "2026-10-02T03:00:01Z", "type" => "cron_job_run_started", "details" => { "cronJobRunId" => "crn-run-3" } }
        ])
        RenderApi.any_instance.expects(:cancel_cron_run).with("crn-1").returns({})
        assert_match "Render is cancelling run crn-run-3 of nightly, going since 2026-10-02T03:00:01Z. Its next scheduled run still starts.",
                     call(:cancel_cron_run, "resource" => "nightly")

        RenderApi.any_instance.stubs(:events).returns([
          { "timestamp" => "2026-10-02T03:04:00Z", "type" => "cron_job_run_ended", "details" => { "cronJobRunId" => "crn-run-3", "status" => "successful" } },
          { "timestamp" => "2026-10-02T03:00:01Z", "type" => "cron_job_run_started", "details" => { "cronJobRunId" => "crn-run-3" } }
        ])
        assert_match "No run of nightly is going now", error(:cancel_cron_run, "resource" => "nightly")
        assert_match "only a cron job has runs to start or cancel", error(:trigger_cron_run, "resource" => "web")
      end

      test "a one-off job runs the exact command on the service, a person is asked every time, and a secret or a service with no jobs is refused" do
        RenderApi.any_instance.expects(:create_job).with("srv-web", "bin/rails db:migrate", plan_id: "plan-srv-006").returns("id" => "job-7", "status" => "pending")
        result = @pack.call("run_job", environment_row: @row, arguments: { "resource" => "web", "command" => "bin/rails db:migrate", "plan" => "plan-srv-006" })
        assert_match "Started one-off job job-7 on web running bin/rails db:migrate, now pending. Follow it with run_history with name job and run job-7.",
                     result["content"].sole["text"]
        assert_includes result["content"].sole["text"], "https://dashboard.render.com/web/srv-web"

        RenderApi.any_instance.expects(:create_job).with("srv-web", "bin/rails runner Repair.call", plan_id: nil).returns("id" => "job-8")
        call(:run_job, "resource" => "web", "command" => "bin/rails runner Repair.call")

        refusal = assert_raises(Integrations::PolicyRefusal) { call(:run_job, "resource" => "web", "command" => "API_TOKEN=ghp_#{'a' * 36} bin/sync") }
        assert_match "looks like a secret", refusal.message
        assert_match "plan must be a Render plan id", error(:run_job, "resource" => "web", "command" => "ls", "plan" => "big")
        assert_match "Render runs one-off jobs from web services", error(:run_job, "resource" => "mailer", "command" => "ls")

        @integration.update!(slug: "render")
        tool = @integration.tools.create!(name: "run_job", description: "Run", read_only: false, enabled: true, params_schema: { "type" => "object" })
        assert Integrations::SafeChanges.access?(tool), "never made without asking, and never allowed for the rest of a chat"
        assert_not Integrations::SafeChanges.tool?(tool)
      end

      test "a one-off job still running is cancelled, and one that ended is refused" do
        RenderApi.any_instance.stubs(:job).with("srv-web", "job-2").returns("id" => "job-2", "status" => "running")
        RenderApi.any_instance.expects(:cancel_job).with("srv-web", "job-2").returns("id" => "job-2", "status" => "canceled")
        assert_match "Render is cancelling one-off job job-2 of web, now canceled.", call(:cancel_job, "resource" => "web", "job" => "job-2")

        RenderApi.any_instance.stubs(:job).with("srv-web", "job-1").returns("id" => "job-1", "status" => "succeeded")
        assert_match "already ended as succeeded", error(:cancel_job, "resource" => "web", "job" => "job-1")
      end

      test "a task is run by its workflow's slug and its name with its input, a secret is never sent, and a run is cancelled while it goes" do
        RenderApi.any_instance.stubs(:workflow).with("wfl-1").returns("id" => "wfl-1", "slug" => "mailer-abc")
        RenderApi.any_instance.expects(:run_task).with("mailer-abc/send_digest", { "day" => "monday" }).returns("id" => "trn-5", "status" => "pending")
        assert_match "Started task run trn-5 of send_digest on mailer, now pending.", call(:run_task, "resource" => "mailer", "task" => "send_digest", "input" => { "day" => "monday" })
        assert_match "has no task nope. Its tasks are send_digest and render_email.", error(:run_task, "resource" => "mailer", "task" => "nope")
        refusal = assert_raises(Integrations::PolicyRefusal) { call(:run_task, "resource" => "mailer", "task" => "send_digest", "input" => [ "ghp_#{'a' * 36}" ]) }
        assert_match "looks like a secret", refusal.message

        RenderApi.any_instance.stubs(:task_run).with("trn-5").returns("id" => "trn-5", "taskId" => "tsk-1", "status" => "running")
        RenderApi.any_instance.expects(:cancel_task_run).with("trn-5").returns(nil)
        assert_match "Render is cancelling task run trn-5 of mailer.", call(:cancel_task_run, "resource" => "mailer", "run" => "trn-5")
        RenderApi.any_instance.stubs(:task_run).with("trn-1").returns("id" => "trn-1", "taskId" => "tsk-1", "status" => "failed")
        assert_match "already ended as failed", error(:cancel_task_run, "resource" => "mailer", "run" => "trn-1")

        RenderApi.any_instance.stubs(:tasks).with("wfl-1").raises(RenderApi::Error, "Render answered 500: oops")
        RenderApi.any_instance.expects(:cancel_task_run).never
        assert_match "could not be read, so task run trn-5 cannot be told to be its own", error(:cancel_task_run, "resource" => "mailer", "run" => "trn-5")
        assert_match "cannot be told to be its own", error(:task_runs, "resource" => "mailer", "run" => "trn-5")
      end

      private

      def error(tool, arguments) = assert_raises(NativePack::Error) { call(tool, arguments) }.message

      def listed(items) = Pages::Read.new(items: items, complete: true)

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
