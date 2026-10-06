require "test_helper"

module Integrations
  module Packs
    class TriggerDevTest < ActiveSupport::TestCase
      DEPLOYED = { "id" => "deployment_2", "version" => "20261002.1", "status" => "DEPLOYED" }.freeze
      DETAILS = DEPLOYED.merge("worker" => { "tasks" => [ { "slug" => "send-email", "filePath" => "src/trigger/email.ts", "exportName" => "sendEmail" },
                                                          { "slug" => "nightly-sync", "filePath" => "src/trigger/sync.ts", "exportName" => "nightlySync" } ] }).freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: TriggerDev::PROVIDER_KEY, name: "Trigger.dev")
        @row = @integration.integration_environments.create!
        TriggerDev.store_credentials!(@row, TriggerDev::API_KEY => " tr_prod_sk_abc ")
        @row.store_fields!(TriggerDev::PROJECT => "proj_acme")
        @pack = TriggerDev.new(@integration)
        TriggerDevApi.any_instance.stubs(:deployments).with(status: TriggerDev::DEPLOYED, limit: TriggerDevApi::MIN_DEPLOYMENT_PAGE).returns([ DEPLOYED ])
        TriggerDevApi.any_instance.stubs(:deployment).with("deployment_2").returns(DETAILS)
        TriggerDevApi.any_instance.stubs(:environment_variables).returns([])
      end

      test "the key is stored trimmed, the project ref is a field of the form, and only promoting a deployment changes anything" do
        assert_equal "tr_prod_sk_abc", @row.reload.credentials_hash[TriggerDev::API_KEY]
        assert_equal [ TriggerDev::API_KEY ], TriggerDev.credential_fields.map(&:key)
        assert_equal [ "promote_deployment" ], TriggerDev.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a key or project ref that cannot be right is refused on the form, and Trigger.dev's own refusal is said there too" do
        assert_equal "Paste a secret API key.", TriggerDev.credential_refusal({})
        assert_match "starts with tr_", TriggerDev.credential_refusal({ TriggerDev::API_KEY => "sk_live_x" }, fields: { TriggerDev::PROJECT => "proj_acme" })
        assert_match "proj_", TriggerDev.credential_refusal({ TriggerDev::API_KEY => "tr_prod_sk_x" }, fields: { TriggerDev::PROJECT => "acme" })
        TriggerDevApi.any_instance.stubs(:runs).raises(TriggerDevApi::Error, "Trigger.dev answered 401: Invalid API key")
        assert_equal "Trigger.dev refused this key: Trigger.dev answered 401: Invalid API key. Check it belongs to the environment you chose and can read runs.",
                     TriggerDev.credential_refusal({ TriggerDev::API_KEY => "tr_prod_sk_x" }, fields: { TriggerDev::PROJECT => "proj_acme" })
        TriggerDevApi.any_instance.stubs(:runs).returns([])
        assert_nil TriggerDev.credential_refusal({ TriggerDev::API_KEY => "tr_prod_sk_x" }, fields: { TriggerDev::PROJECT => "proj_acme" })
      end

      test "the newest deployed version's tasks go on the map as jobs of the project, with no page to link" do
        snapshot = @pack.map_of(@row)

        assert_equal %w[send-email nightly-sync], snapshot.resources.map(&:external_id)
        task = snapshot.resources.first
        assert_equal [ ResourceMap::KIND_JOB, "proj_acme", nil, "deployed" ], [ task.kind, task.account, task.url, task.status ]
        assert_equal({ "version" => "20261002.1", "file" => "src/trigger/email.ts" }, task.details)
        assert_empty snapshot.gaps
      end

      test "the environment's variables are read in memory for every task, a secret by its name, from the key's own environment" do
        TriggerDevApi.any_instance.expects(:environment_variables).with("proj_acme", "prod").returns([
          { "name" => "DATABASE_URL", "value" => "postgres://app:task-pass@db.example.com:6543/app", "isSecret" => false },
          { "name" => "UPSTASH_REDIS_REST_TOKEN", "value" => "<redacted>", "isSecret" => true }
        ])

        snapshot = @pack.map_of(@row)

        assert_equal [ %w[DATABASE_URL UPSTASH_REDIS_REST_TOKEN] ] * 2, snapshot.uses.group_by(&:from).values.map { |uses| uses.map(&:variable).sort }
        assert_equal 6543, snapshot.uses.find { |use| use.variable == "DATABASE_URL" }.port
        assert_no_setting_values(snapshot, "task-pass", "db.example.com")
      end

      test "a key whose preset cannot read variables is a gap that names what it lacks and holds no task back" do
        TriggerDevApi.any_instance.stubs(:environment_variables).raises(TriggerDevApi::Error, "Trigger.dev answered 403: Unauthorized")

        snapshot = @pack.map_of(@row)

        assert_equal 2, snapshot.resources.size
        assert snapshot.complete?
        assert_not snapshot.settings_complete?
        assert_equal "Trigger.dev refused the environment's variables: Trigger.dev answered 403: Unauthorized. So the tasks are not linked to what " \
                     "their variables name. This is optional. Observer keeps the connection read only and cannot read environment variables, " \
                     "and a key whose preset can read them links the tasks too.", snapshot.gaps.sole.text
      end

      test "a list of queues cut short at its page bound says so" do
        TriggerDevApi.any_instance.stubs(:queues).returns(Pages::Read.new(items: [ { "name" => "send-email", "type" => "task", "running" => 1, "queued" => 3 } ], complete: false))
        TriggerDevApi.any_instance.stubs(:concurrency_limits).returns(Pages::Read.new(items: [], complete: true))

        assert_match "1 queues, most waiting first. Only the first 1 queues were read.", call(:list_queues, {})
      end

      test "an environment with nothing deployed says so on the map rather than failing" do
        TriggerDevApi.any_instance.stubs(:deployments).returns([])

        snapshot = @pack.map_of(@row)

        assert_empty snapshot.resources
        assert_equal [ ResourceMap::Gap.new(text: "Nothing is deployed to this environment, so it has no tasks to read.", kinds: []) ], snapshot.gaps
      end

      test "runs are listed newest first, filtered as asked, each with its page in the dashboard" do
        TriggerDevApi.any_instance.expects(:runs).with do |filter:, limit:|
          filter["taskIdentifier"] == [ "send-email" ] && filter["status"] == [ "FAILED" ] && filter["error"] == "error_1" && limit == 5
        end.returns([ { "id" => "run_b", "taskIdentifier" => "send-email", "status" => "FAILED", "createdAt" => "2026-10-03T10:00:00Z", "version" => "20261002.1" } ])

        text = call(:list_runs, "task" => "send-email", "status" => %w[FAILED SPLINES], "error" => "error_1", "limit" => 5)

        assert_match "run_b, send-email, FAILED, version 20261002.1, https://cloud.trigger.dev/projects/v3/proj_acme/runs/run_b", text
        assert_match %r{link with what you found: https://cloud\.trigger\.dev/projects/v3/proj_acme/runs/run_b\z}, text
      end

      test "a run's details carry its attempts, errors and logs, never its payload or output, and nothing credential-like reaches the model" do
        TriggerDevApi.any_instance.stubs(:run).with("run_b").returns(
          "id" => "run_b", "taskIdentifier" => "send-email", "status" => "CRASHED", "version" => "20261002.1", "createdAt" => "2026-10-03T10:00:00Z",
          "payload" => { "email" => "someone@customer.com" }, "output" => { "secret" => "x" },
          "attempts" => [ { "status" => "FAILED", "error" => { "name" => "Error", "message" => "TASK_PROCESS_OOM_KILLED",
                                                               "stackTrace" => "Error: TASK_PROCESS_OOM_KILLED\n at send (email.ts:12)" } } ]
        )
        TriggerDevApi.any_instance.stubs(:run_events).with("run_b").returns([
          { "message" => "sending with key ghp_#{'a' * 36}", "level" => "LOG", "startTime" => "1791021600000000000" },
          { "message" => "", "startTime" => "1791021601000000000" }
        ])

        tool = @integration.tools.create!(name: "run_details", description: "Run", read_only: true, enabled: true, params_schema: { "type" => "object" })
        text = NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "run" => "run_b" })["content"].sole["text"]

        assert_match "Run run_b of send-email, CRASHED", text
        assert_match "Attempt 1, FAILED, started not yet, completed not yet, Error: TASK_PROCESS_OOM_KILLED\nError: TASK_PROCESS_OOM_KILLED", text
        assert_match "1 log lines for run run_b", text
        assert_match "LOG sending with key [REDACTED:github_token]", text
        assert_no_match "someone@customer.com", text
        assert_match "payload, output and metadata are left out", text
      end

      test "a task's logs are read from its latest runs, filtered, newest first" do
        TriggerDevApi.any_instance.stubs(:runs).returns([ { "id" => "run_a" }, { "id" => "run_b" } ])
        TriggerDevApi.any_instance.stubs(:run_events).with("run_a").returns([ { "message" => "timeout calling smtp", "startTime" => "1791021600000000000" },
                                                                              { "message" => "healthcheck ok", "startTime" => "1791021602000000000" } ])
        TriggerDevApi.any_instance.stubs(:run_events).with("run_b").returns([ { "message" => "timeout calling smtp again", "startTime" => "1791021660000000000" } ])

        text = call(:search_task_logs, "task" => "send-email", "regex" => "time.ut", "exclude" => "again")

        assert_match "1 log lines for the latest 2 runs of send-email", text
        assert_match "run_a timeout calling smtp", text
        assert_no_match "healthcheck", text
        assert_raises(NativePack::Error) { call(:search_task_logs, "task" => "send-email", "regex" => "(") }
        assert_raises(NativePack::Error) { call(:search_task_logs, "task" => "send-email' OR 1=1") }
      end

      test "a task's status names its version, its queue and how its last hour went" do
        TriggerDevApi.any_instance.stubs(:queues).returns(Pages::Read.new(items: [ { "name" => "send-email", "type" => "task", "running" => 2, "queued" => 40, "paused" => true, "concurrencyLimit" => 2 } ], complete: true))
        TriggerDevApi.any_instance.stubs(:runs).returns([ { "status" => "COMPLETED" }, { "status" => "FAILED" }, { "status" => "FAILED" } ])

        text = call(:describe_task, "task" => "send-email")

        assert_match "Deployed in version 20261002.1, defined in src/trigger/email.ts as sendEmail", text
        assert_match "Queue send-email (task), 2 executing, 40 waiting, paused, limit 2", text
        assert_match "Runs in the last hour: 2 FAILED, 1 COMPLETED", text
        assert_match "no link to give", text
      end

      test "deployments are listed with what rollback takes, and errors grouped most frequent first" do
        TriggerDevApi.any_instance.stubs(:deployments).with(status: nil, limit: 20).returns([
          { "id" => "deployment_2", "version" => "20261002.1", "status" => "FAILED", "createdAt" => "2026-10-02T09:00:00Z", "error" => { "message" => "build failed" } }
        ])
        TriggerDevApi.any_instance.stubs(:errors).returns([
          { "id" => "error_1", "count" => 3, "errorType" => "TypeError", "errorMessage" => "x is undefined", "taskIdentifier" => "send-email", "status" => "unresolved" },
          { "id" => "error_2", "count" => 9, "errorType" => "Error", "errorMessage" => "timeout", "taskIdentifier" => "send-email", "status" => "unresolved" }
        ])

        assert_match "version 20261002.1, FAILED, id deployment_2, error {\"message\":\"build failed\"}", call(:list_deployments)
        errors = call(:list_errors, "task" => "send-email")
        assert errors.index("9 times: Error: timeout") < errors.index("3 times: TypeError")
      end

      test "metrics are counted per step with empty steps as zero, and CPU is read as a percentage" do
        TriggerDevApi.any_instance.stubs(:query).with { |trql, **| trql.include?("FROM runs") && trql.include?("task_identifier = 'send-email'") }.returns([
          { "bucket" => "2026-10-03 10:00:00", "runs" => 4, "failed" => 1 }, { "bucket" => "2026-10-03 10:05:00", "runs" => 2, "failed" => 0 },
          { "bucket" => "2026-10-03 10:15:00", "runs" => 6, "failed" => 0 }
        ])
        TriggerDevApi.any_instance.stubs(:query).with { |trql, **| trql.include?("process.cpu.utilization") }.returns([ { "bucket" => "2026-10-03 10:00:00", "value" => 0.5 } ])

        result = @pack.call("task_metrics", environment_row: @row,
                                            arguments: { "task" => "send-email", "metrics" => %w[requests cpu], "start" => "2026-10-03T10:00:00Z", "end" => "2026-10-03T10:15:00Z" })

        charts = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS)
        assert_equal [ [ "2026-10-03T10:00:00Z", 4.0 ], [ "2026-10-03T10:05:00Z", 2.0 ], [ "2026-10-03T10:10:00Z", 0.0 ], [ "2026-10-03T10:15:00Z", 6.0 ] ], charts.first.dig("series", 0, "points")
        assert_equal [ [ "2026-10-03T10:00:00Z", 50.0 ] ], charts.last.dig("series", 0, "points")
        assert_match "counted per 5.0 minutes", result["content"].sole["text"]
      end

      test "a week of runs becomes a per minute baseline for every task, with quiet steps as zero" do
        tasks = %w[send-email nightly-sync].map do |slug|
          ResourceMap::Resource.create!(workspace: @workspace, provider: TriggerDev::PROVIDER_KEY, account: "proj_acme", kind: ResourceMap::KIND_JOB,
                                        external_id: slug, name: slug, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
        end
        window = Time.utc(2026, 10, 1, 0, 0)..Time.utc(2026, 10, 1, 0, 30)
        TriggerDevApi.any_instance.stubs(:query).with { |trql, **| trql.include?("FROM runs") }.returns([
          { "task" => "send-email", "bucket" => "2026-10-01 00:00:00", "runs" => 10, "failed" => 2 },
          { "task" => "send-email", "bucket" => "2026-10-01 00:10:00", "runs" => 20, "failed" => 0 }
        ])
        TriggerDevApi.any_instance.stubs(:query).with { |trql, **| trql.include?("process.memory.usage") }.returns([
          { "task" => "nightly-sync", "bucket" => "2026-10-01 00:00:00", "value" => 104_857_600 }
        ])
        TriggerDevApi.any_instance.stubs(:query).with { |trql, **| trql.include?("process.cpu.utilization") }.returns([])

        found = @pack.baselines_of(@row, tasks, window)

        requests = found.find { |reading| reading.key == tasks.first.key && reading.metric == "requests" }
        assert_equal [ 1.0, 2.0, 0.0, 0.0 ], requests.points.map(&:last)
        assert_equal TriggerDev::PER_MINUTE, requests.unit
        memory = found.find { |reading| reading.metric == "memory" }
        assert_equal [ tasks.last.key, [ 100.0 ] ], [ memory.key, memory.points.map(&:last) ]
      end

      test "promoting a version says it moves every task, and a key that may not deploy is told what to do" do
        TriggerDevApi.any_instance.expects(:promote).with("20261001.1").returns({ "version" => "20261001.1" })
        assert_match "for every task in it", call(:promote_deployment, "version" => "20261001.1")

        TriggerDevApi.any_instance.stubs(:promote).raises(TriggerDevApi::Error, "Trigger.dev answered 403: Forbidden")
        error = assert_raises(NativePack::Error) { call(:promote_deployment, "version" => "20261001.1") }
        assert_match "create a key whose preset can deploy", error.message
        assert_raises(NativePack::Error) { call(:promote_deployment, "version" => "../runs") }
      end

      test "the health check reads runs with the key, and says why it cannot" do
        TriggerDevApi.any_instance.stubs(:runs).raises(TriggerDevApi::Error, "Trigger.dev answered 401: Invalid API key")

        error = assert_raises(NativePack::Error) { @pack.check_health!(@row) }

        assert_equal "Trigger.dev answered 401: Invalid API key", error.message
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
