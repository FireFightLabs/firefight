require "test_helper"

module Integrations
  module Packs
    class DigitaloceanTest < ActiveSupport::TestCase
      APP_ID = "4f6c71e2-1e90-4762-9fee-6cc4a0a9f2cf".freeze
      SPEC = {
        "name" => "shop", "region" => "fra",
        "services" => [ { "name" => "web", "instance_count" => 2, "instance_size_slug" => "apps-s-1vcpu-1gb",
                          "github" => { "repo" => "acme/shop", "branch" => "main" }, "http_port" => 8080,
                          "envs" => [ { "key" => "DATABASE_URL", "value" => "postgres://app:hunter2@db/prod", "type" => "SECRET" } ],
                          "health_check" => { "http_path" => "/up" } } ],
        "workers" => [ { "name" => "jobs", "autoscaling" => { "min_instance_count" => 1, "max_instance_count" => 4 },
                         "github" => { "repo" => "acme/shop", "branch" => "main" } } ],
        "domains" => [ { "domain" => "shop.acme.dev" } ]
      }.freeze
      APP = {
        "id" => APP_ID, "spec" => SPEC, "live_domain" => "shop-abc.ondigitalocean.app", "region" => { "slug" => "fra" },
        "active_deployment" => { "id" => "dep-2", "phase" => "ACTIVE", "created_at" => "2026-10-01T10:00:00Z", "cause" => "commit abc pushed to github/acme/shop",
                                 "services" => [ { "name" => "web", "source_commit_hash" => "abc1234567890def" } ] }
      }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Digitalocean::PROVIDER_KEY, name: "DigitalOcean")
        @row = @integration.integration_environments.create!
        Digitalocean.store_credentials!(@row, Digitalocean::API_TOKEN => " dop-token ")
        @pack = Digitalocean.new(@integration)
        DigitaloceanApi.any_instance.stubs(:apps).returns(listed(APP))
        DigitaloceanApi.any_instance.stubs(:app).returns(APP.deep_dup)
        DigitaloceanApi.any_instance.stubs(:droplets).returns(listed({ "id" => 3164494, "name" => "bastion", "status" => "active", "size_slug" => "s-1vcpu-1gb",
                                                                   "region" => { "slug" => "fra1" } }))
        DigitaloceanApi.any_instance.stubs(:databases).returns(listed({ "id" => "db-1", "name" => "shop-db", "engine" => "mysql", "status" => "online",
                                                                    "version" => "8", "num_nodes" => 1, "size" => "db-s-1vcpu-1gb", "region" => "fra1",
                                                                    "connection" => { "password" => "s3cret" } }))
        DigitaloceanApi.any_instance.stubs(:account).returns("uuid" => "acc-1", "team" => { "name" => "Acme" })
        DigitaloceanApi.any_instance.stubs(:alerts).returns([])
        DigitaloceanApi.any_instance.stubs(:droplet_actions).returns([])
        DigitaloceanApi.any_instance.stubs(:job_invocations).returns([])
      end

      test "the token is stored trimmed, a wrong one is said on the form, and only the changes are not read only" do
        assert_equal "dop-token", @row.reload.credentials_hash[Digitalocean::API_TOKEN]
        assert_equal %w[cancel_deployment cancel_job_run cancel_autoscaling redeploy_app commit_rollback revert_rollback rollback_app restart_app scale_app reboot_droplet], Digitalocean.tool_definitions.reject(&:read_only).map(&:name)
        DigitaloceanApi.any_instance.stubs(:account).raises(DigitaloceanApi::Error, "DigitalOcean answered 401: Unable to authenticate you")
        assert_equal "DigitalOcean refused this token: DigitalOcean answered 401: Unable to authenticate you.",
                     Digitalocean.credential_refusal({ Digitalocean::API_TOKEN => "dop-bad" })
        assert_equal "Paste a personal access token.", Digitalocean.credential_refusal({})
        assert_equal "DigitalOcean refused this token: DigitalOcean answered 401: Unable to authenticate you.",
                     Integrations::Credentials.refusal(Digitalocean::PROVIDER_KEY, { Digitalocean::API_TOKEN => "dop-bad" }, region: nil, fields: {})
        assert_raises(Integrations::Error) { @pack.check_health!(@row) }
      end

      test "an app's status names its deployments and components with their health, never an environment value" do
        DigitaloceanApi.any_instance.stubs(:health).returns("components" => [ { "name" => "web", "state" => "UNHEALTHY", "replicas_ready" => 1, "replicas_desired" => 2 } ])

        text = call(:describe_resource, "resource" => "shop")

        assert_match "Active deployment: dep-2, ACTIVE", text
        assert_match "- web (service): 2 instances, apps-s-1vcpu-1gb, github acme/shop branch main, UNHEALTHY, 1 of 2 ready", text
        assert_match "- jobs (worker): autoscales 1 to 4", text
        assert_no_match "hunter2", text
        assert_no_match "DATABASE_URL", text
        assert_match %r{link with what you found: https://cloud\.digitalocean\.com/apps/#{APP_ID}\z}, text
      end

      test "a database's status leaves out its connection and users" do
        DigitaloceanApi.any_instance.stubs(:database).returns(DigitaloceanApi.new("x").databases.items.first)

        text = call(:describe_resource, "resource" => "shop-db")

        assert_match "shop-db, mysql 8 database, online", text
        assert_no_match "s3cret", text
        assert_match %r{https://cloud\.digitalocean\.com/databases\z}, text
      end

      test "logs are the newest lines in range, filtered, and every answer is redacted on its way out of the executor" do
        DigitaloceanApi.any_instance.expects(:logs).with(APP_ID, type: "RUN_RESTARTED", component: "web", deployment: nil).twice.returns(historic: [ "https://logs.example/1.log" ], live: nil)
        DigitaloceanApi.any_instance.stubs(:log_file).returns(<<~LOG)
          web 2026-10-01T10:00:00Z booting
          web 2026-10-01T10:01:00Z error token ghp_#{'a' * 36}
          web 2026-10-01T10:02:00Z error out of memory
        LOG

        text = call(:app_logs, "resource" => "shop", "component" => "web", "type" => "RUN_RESTARTED", "text" => "error",
                               "start" => "2026-10-01T09:00:00Z", "end" => "2026-10-01T11:00:00Z")

        assert_match "2 log lines", text
        assert text.index("out of memory") < text.index("error token"), "newest first"
        assert_no_match "booting", text
        tool = @integration.tools.create!(name: "app_logs", description: "Logs", read_only: true, enabled: true, params_schema: {})
        redacted = NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "resource" => "shop", "component" => "web", "type" => "RUN_RESTARTED",
                                                                                    "start" => "2026-10-01T09:00:00Z", "end" => "2026-10-01T11:00:00Z" })
        assert_match "REDACTED:github_token", redacted["content"].sole["text"]
      end

      test "a regular expression that takes too long is refused as too slow, not as unreadable" do
        DigitaloceanApi.any_instance.stubs(:logs).returns(historic: [ "https://logs.example/1.log" ], live: nil)
        DigitaloceanApi.any_instance.stubs(:log_file).returns("web 2026-10-01T10:00:00Z #{'a' * 35}\n")

        error = assert_raises(NativePack::Error) do
          call(:app_logs, "resource" => "shop", "regex" => "(?=(a+)+b)", "start" => "2026-10-01T09:00:00Z", "end" => "2026-10-01T11:00:00Z")
        end
        assert_match "took too long", error.message
      end

      test "a deployment list names each id, phase and commit, for a rollback" do
        DigitaloceanApi.any_instance.stubs(:deployments).returns([ APP["active_deployment"].merge("id" => "dep-2"),
                                                                    { "id" => "dep-1", "phase" => "SUPERSEDED", "created_at" => "2026-09-30T10:00:00Z" } ])

        text = call(:list_deployments, "resource" => APP_ID)

        assert_match "2026-10-01T10:00:00Z, deployment dep-2, ACTIVE, commit abc pushed to github/acme/shop, commits web abc123456789", text
        assert_match "deployment dep-1, SUPERSEDED", text
      end

      test "deployments are kept as deploys, the active one live and its commit where every component shares one" do
        DigitaloceanApi.any_instance.stubs(:deployments).returns([
          { "id" => "dep-3", "phase" => "DEPLOYING", "created_at" => "2026-10-02T10:00:00Z",
            "services" => [ { "name" => "web", "source_commit_hash" => "def4567" } ], "workers" => [ { "name" => "jobs", "source_commit_hash" => "fed7654" } ] },
          APP["active_deployment"].merge("phase_last_updated_at" => "2026-10-01T10:05:00Z"),
          { "id" => "dep-1", "phase" => "SUPERSEDED", "created_at" => "2026-09-30T10:00:00Z", "phase_last_updated_at" => "2026-09-30T10:06:00Z" }
        ])

        result = @pack.call("list_deployments", environment_row: @row, arguments: { "resource" => APP_ID })
        deploys = Capabilities::Deploys.deploys_of(result)

        assert_equal [
          [ "dep-3", nil, Capabilities::History::RUNNING, nil, nil ],
          [ "dep-2", "abc1234567890def", Capabilities::History::SUCCEEDED, true, Time.utc(2026, 10, 1, 10, 5) ],
          [ "dep-1", nil, Capabilities::History::SUCCEEDED, false, Time.utc(2026, 9, 30, 10, 6) ]
        ], deploys.map { |deploy| [ deploy.id, deploy.commit, deploy.status, deploy.live, deploy.finished_at ] }
        assert_equal Time.utc(2026, 10, 2, 10), deploys.first.started_at
        assert_equal "dep-2", Capabilities::Deploys.live(deploys).id
        assert_match "deployment dep-3, DEPLOYING, commits web def4567", result["content"].sole["text"]
      end

      test "an app's metrics are charted per instance, and a Droplet's CPU is worked out from its counters" do
        DigitaloceanApi.any_instance.stubs(:metrics).with("apps/cpu_percentage", has_entry("app_id", APP_ID))
                       .returns([ { "metric" => { "app_component_instance" => "web-0" }, "values" => [ [ 1_759_312_800, "12.5" ], [ 1_759_312_920, "30" ] ] } ])
        result = @pack.call("resource_metrics", environment_row: @row, arguments: { "resource" => "shop", "metrics" => [ "cpu" ] })

        assert_equal "web-0", result.dig("structuredContent", "charts", 0, "series", 0, "label")
        assert_equal [ 12.5, 30.0 ], result.dig("structuredContent", "charts", 0, "series", 0, "points").map(&:last)

        DigitaloceanApi.any_instance.stubs(:metrics).with("droplet/cpu", has_entry("host_id", "3164494"))
                       .returns([ { "metric" => { "mode" => "idle" }, "values" => [ [ 100, "10" ], [ 160, "40" ] ] },
                                  { "metric" => { "mode" => "user" }, "values" => [ [ 100, "5" ], [ 160, "15" ] ] } ])
        droplet = @pack.call("resource_metrics", environment_row: @row, arguments: { "resource" => "bastion", "metrics" => [ "cpu" ] })

        assert_equal [ 25.0 ], droplet.dig("structuredContent", "charts", 0, "series", 0, "points").map(&:last)
        assert_raises(Integrations::Error) { call(:resource_metrics, "resource" => "bastion", "metrics" => [ "restarts" ]) }
      end

      test "only a MySQL database has metrics" do
        DigitaloceanApi.any_instance.stubs(:database).returns("engine" => "pg")

        error = assert_raises(Integrations::Error) { call(:resource_metrics, "resource" => "shop-db") }

        assert_match "only for MySQL databases", error.message
      end

      test "a rollback is checked first, goes to the deployment named and says how to keep or undo it" do
        DigitaloceanApi.any_instance.expects(:validate_rollback).with(APP_ID, "dep-1").returns(
          "valid" => true, "warnings" => [ { "code" => "image_source_missing_digest", "components" => [ "worker" ],
                                             "message" => "one or more components are missing an image digest" } ]
        )
        DigitaloceanApi.any_instance.expects(:rollback).with(APP_ID, "dep-1").returns("deployment" => { "id" => "dep-3" })

        text = call(:rollback_app, "resource" => "shop", "deployment" => "dep-1")

        assert text.start_with?("shop is rolling back to deployment dep-1, as new deployment dep-3. DigitalOcean warned: one or more " \
                                "components are missing an image digest (worker). DigitalOcean pins the app")
        assert_match "kept with commit_rollback or undone with revert_rollback", text
      end

      test "a rollback DigitalOcean says it cannot make is refused with its reason, and nothing is rolled back" do
        DigitaloceanApi.any_instance.stubs(:validate_rollback).returns("valid" => false,
                                                                       "error" => { "code" => "incompatible_result", "message" => "deployment result \"failed\" is unsuitable for rollback" })
        DigitaloceanApi.any_instance.expects(:rollback).never

        error = assert_raises(NativePack::Error) { call(:rollback_app, "resource" => "shop", "deployment" => "dep-1") }

        assert_equal "DigitalOcean cannot roll shop back to deployment dep-1: deployment result \"failed\" is unsuitable for rollback.", error.message
      end

      test "a pinned app's rollback is kept or undone, and an app that is not pinned is refused" do
        pinned = APP.deep_dup.merge("pinned_deployment" => { "id" => "dep-1" })
        DigitaloceanApi.any_instance.stubs(:app).returns(pinned)
        DigitaloceanApi.any_instance.expects(:commit_rollback).with(APP_ID).returns({})
        DigitaloceanApi.any_instance.expects(:revert_rollback).with(APP_ID).returns("deployment" => { "id" => "dep-4" })

        assert_match "shop keeps deployment dep-1 for good and deploys again", call(:commit_rollback, "resource" => "shop")
        assert_match "as deployment dep-4, and deploys again on a push", call(:revert_rollback, "resource" => "shop")
        assert_match "pinned to deployment dep-1 by a rollback", assert_raises(NativePack::Error) { call(:redeploy_app, "resource" => "shop") }.message

        DigitaloceanApi.any_instance.stubs(:app).returns(APP.deep_dup)
        assert_match "not pinned by a rollback", assert_raises(NativePack::Error) { call(:commit_rollback, "resource" => "shop") }.message
      end

      test "a redeploy builds the newest commit, from source when asked" do
        DigitaloceanApi.any_instance.expects(:create_deployment).with(APP_ID, force_build: true).returns("deployment" => { "id" => "dep-5" })

        text = call(:redeploy_app, "resource" => "shop", "force_build" => true)

        assert_match "shop is deploying the newest commit of each component's branch, built again from source, as deployment dep-5.", text
        assert_match "https://cloud.digitalocean.com/apps/#{APP_ID}/deployments/dep-5", text
      end

      test "a deployment still going is cancelled, and one that ended is refused" do
        DigitaloceanApi.any_instance.stubs(:deployment).with(APP_ID, "dep-3").returns("id" => "dep-3", "phase" => "BUILDING")
        DigitaloceanApi.any_instance.expects(:cancel_deployment).with(APP_ID, "dep-3").returns("id" => "dep-3", "phase" => "CANCELED")

        assert_match "Deployment dep-3 of shop is cancelled, now CANCELED. The deployment live before it keeps serving.", call(:cancel_deployment, "resource" => "shop", "deployment" => "dep-3")

        DigitaloceanApi.any_instance.stubs(:deployment).with(APP_ID, "dep-2").returns("id" => "dep-2", "phase" => "ACTIVE")
        assert_match "already ended, ACTIVE", assert_raises(NativePack::Error) { call(:cancel_deployment, "resource" => "shop", "deployment" => "dep-2") }.message
      end

      JOB_RUN = { "id" => "inv-1", "job_name" => "migrate", "deployment_id" => "dep-2", "phase" => "FAILED", "created_at" => "2026-10-01T11:00:00Z",
                  "started_at" => "2026-10-01T11:00:05Z", "completed_at" => "2026-10-01T11:01:05Z",
                  "trigger" => { "type" => "SCHEDULE", "scheduled" => { "schedule" => { "cron" => "0 * * * *" } } } }.freeze

      test "a job's runs are run history beside the deployments, and one run by its id carries its log" do
        DigitaloceanApi.any_instance.stubs(:deployments).returns([ APP["active_deployment"].merge("phase_last_updated_at" => "2026-10-01T10:05:00Z") ])
        DigitaloceanApi.any_instance.stubs(:job_invocations).with(APP_ID, limit: 20).returns([ JOB_RUN ])

        runs = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => APP_ID }))
        assert_equal [ [ "inv-1", "job migrate", "failed", 60 ], [ "dep-2", "deploy", "succeeded", 300 ] ], runs.map { |run| [ run.id, run.name, run.status, run.seconds ] }
        assert_equal "on schedule 0 * * * *, deployment dep-2", runs.first.detail

        DigitaloceanApi.any_instance.stubs(:deployment).raises(DigitaloceanApi::NotFound, "DigitalOcean answered 404: not found")
        DigitaloceanApi.any_instance.stubs(:job_invocation).with(APP_ID, "inv-1").returns(JOB_RUN)
        one = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => APP_ID, "run" => "inv-1" })).sole
        assert_equal({ "resource" => APP_ID, "job_invocation" => "inv-1", "component" => "migrate" }, one.first_failed_part.log[Capabilities::History::LOG_ARGUMENTS])
        assert_equal [ "dep-2" ], Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => APP_ID, "name" => "deploy" })).map(&:id)
      end

      test "a job run's logs are read under its job, and a run still going is cancelled under it" do
        DigitaloceanApi.any_instance.stubs(:job_invocation).with(APP_ID, "inv-1").returns(JOB_RUN.merge("phase" => "RUNNING"))
        DigitaloceanApi.any_instance.expects(:job_invocation_logs).with(APP_ID, "migrate", "inv-1").returns(historic: [], live: "wss://logs.example/live?token=x")
        DigitaloceanApi.any_instance.expects(:live_log).with("wss://logs.example/live?token=x").returns("migrate 2026-10-01T11:00:30Z applying 0042\n")

        text = call(:app_logs, "resource" => "shop", "job_invocation" => "inv-1")
        assert_match "job run inv-1 logs of shop", text
        assert_match "applying 0042", text
        assert_no_match "token=x", text

        DigitaloceanApi.any_instance.expects(:cancel_job_invocation).with(APP_ID, "inv-1", job_name: "migrate").returns("phase" => "CANCELED")
        assert_match "Run inv-1 of job migrate in shop is cancelled", call(:cancel_job_run, "resource" => "shop", "run" => "inv-1")
      end

      test "a deployment's live log is read beside its archived files, and one that cannot be read is said" do
        DigitaloceanApi.any_instance.stubs(:logs).returns(historic: [ "https://logs.example/build.log" ], live: "wss://logs.example/live")
        DigitaloceanApi.any_instance.stubs(:log_file).returns("web 2026-10-01T06:01:00Z npm ci\n")
        DigitaloceanApi.any_instance.stubs(:live_log).returns("web 2026-10-01T06:02:00Z compiling\n")

        text = call(:app_logs, "resource" => "shop", "deployment" => "dep-9", "type" => "BUILD")
        assert_match "compiling", text
        assert_match "npm ci", text

        DigitaloceanApi.any_instance.stubs(:live_log).raises(DigitaloceanApi::Error, "could not reach logs.example (Errno::ECONNREFUSED)")
        text = call(:app_logs, "resource" => "shop", "deployment" => "dep-9", "type" => "BUILD")
        assert_match "npm ci", text
        assert_match "The live log could not be read, so only the archived lines are here", text
      end

      test "an app's events say its deployments and how autoscaling moved each component" do
        DigitaloceanApi.any_instance.expects(:events).with(APP_ID, limit: 20, type: nil).returns([
          { "id" => "ev-2", "type" => "AUTOSCALING", "created_at" => "2026-10-01T12:00:00Z",
            "autoscaling" => { "phase" => "SUCCEEDED", "components" => { "web" => { "from" => 2, "to" => 4, "triggering_metric" => "cpu" } } } },
          { "id" => "ev-1", "type" => "DEPLOYMENT", "deployment_id" => "dep-2", "created_at" => "2026-10-01T10:00:00Z",
            "deployment" => { "phase" => "ACTIVE", "cause" => "manual" } }
        ])

        text = call(:app_events, "resource" => "shop")

        assert_match "- 2026-10-01T12:00:00Z: autoscaling SUCCEEDED, web 2 to 4 on cpu, event ev-2", text
        assert_match "- 2026-10-01T10:00:00Z: deployment dep-2, ACTIVE, manual", text
      end

      test "an autoscaling still going is cancelled, and a deployment or one that ended is refused" do
        DigitaloceanApi.any_instance.stubs(:event).with(APP_ID, "ev-2").returns("id" => "ev-2", "type" => "AUTOSCALING", "autoscaling" => { "phase" => "IN_PROGRESS" })
        DigitaloceanApi.any_instance.expects(:cancel_event).with(APP_ID, "ev-2").returns("id" => "ev-2", "autoscaling" => { "phase" => "CANCELED" })
        assert_match "The autoscaling ev-2 of shop is cancelled, now CANCELED. Its components keep the instances they run now.",
                     call(:cancel_autoscaling, "resource" => "shop", "event" => "ev-2")

        DigitaloceanApi.any_instance.stubs(:event).with(APP_ID, "ev-3").returns("id" => "ev-3", "type" => "AUTOSCALING", "autoscaling" => { "phase" => "SUCCEEDED" })
        assert_match "already ended, SUCCEEDED", assert_raises(NativePack::Error) { call(:cancel_autoscaling, "resource" => "shop", "event" => "ev-3") }.message
        DigitaloceanApi.any_instance.stubs(:event).with(APP_ID, "ev-1").returns("id" => "ev-1", "type" => "DEPLOYMENT")
        assert_match "only an autoscaling is cancelled", assert_raises(NativePack::Error) { call(:cancel_autoscaling, "resource" => "shop", "event" => "ev-1") }.message
      end

      test "an app's status names its alerts without where they are sent, and a Droplet's its latest actions" do
        DigitaloceanApi.any_instance.stubs(:health).returns({})
        DigitaloceanApi.any_instance.stubs(:alerts).returns([
          { "id" => "al-1", "component_name" => "web", "phase" => "ACTIVE",
            "spec" => { "rule" => "CPU_UTILIZATION", "operator" => "GREATER_THAN", "value" => 80, "window" => "FIVE_MINUTES" },
            "emails" => [ "ops@acme.dev" ], "slack_webhooks" => [ { "url" => "https://hooks.slack.com/services/T0/B0/secret", "channel" => "ops" } ] }
        ])
        text = call(:describe_resource, "resource" => "shop")
        assert_match "- CPU_UTILIZATION, GREATER_THAN 80 over FIVE_MINUTES, on web, ACTIVE, sent to 1 emails and 1 Slack channels", text
        assert_no_match "hooks.slack.com", text
        assert_no_match "ops@acme.dev", text

        DigitaloceanApi.any_instance.stubs(:droplet).returns("id" => 3164494, "name" => "bastion", "status" => "active", "created_at" => "2026-01-01T00:00:00Z")
        DigitaloceanApi.any_instance.stubs(:droplet_actions).with("3164494", limit: Digitalocean::DROPLET_ACTIONS).returns([
          { "id" => 2, "type" => "reboot", "status" => "completed", "started_at" => "2026-10-01T09:00:00Z", "completed_at" => "2026-10-01T09:01:00Z" }
        ])
        assert_match "- reboot completed, started 2026-10-01T09:00:00Z, ended 2026-10-01T09:01:00Z", call(:describe_resource, "resource" => "bastion")
      end

      test "an app is read again on its own after it changed, linked to the database it attaches, and one gone is gone" do
        attached = APP.deep_dup
        attached["spec"]["databases"] = [ { "name" => "db", "cluster_name" => "shop-db" } ]
        DigitaloceanApi.any_instance.stubs(:app).returns(attached)
        scope = ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_SERVICE, external_id: APP_ID)

        snapshot = @pack.map_refresh(@row, scope)

        assert_includes snapshot.resources.map(&:name), "shop"
        assert_not_includes snapshot.resources.map(&:kind), ResourceMap::KIND_DATABASE
        assert(snapshot.links.any? { |link| link.relation == ResourceMap::RELATION_USES && link.to.last == "db-1" })
        DigitaloceanApi.any_instance.stubs(:app).raises(DigitaloceanApi::NotFound, "DigitalOcean answered 404: not found")
        assert_equal [ [ Digitalocean::PROVIDER_KEY, "Acme", ResourceMap::KIND_SERVICE, APP_ID ] ], @pack.map_refresh(@row, scope).gone
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_DATABASE, external_id: "db-1"))
      end

      test "scaling changes one instance count and sends the rest of the spec back as it came" do
        DigitaloceanApi.any_instance.expects(:update_app).with do |id, spec|
          id == APP_ID && spec.dig("services", 0, "instance_count") == 5 && spec.except("services") == SPEC.except("services") &&
            spec.dig("services", 0, "envs") == SPEC.dig("services", 0, "envs")
        end.returns({})

        assert_equal "web of shop goes from 2 to 5 instances, redeploying the same code.", call(:scale_app, "resource" => "shop", "component" => "web", "instances" => 5).lines.first.strip
        assert_match "autoscales", assert_raises(Integrations::Error) { call(:scale_app, "resource" => "shop", "component" => "jobs", "instances" => 2) }.message
        assert_match "call scale_app with the component", assert_raises(Integrations::Error) { call(:scale_app, "resource" => "shop", "instances" => 2) }.message
        assert_raises(Integrations::Error) { call(:scale_app, "resource" => "shop", "component" => "web", "instances" => 0) }
      end

      test "a fractional or non-finite instance count is refused, never rounded down" do
        DigitaloceanApi.any_instance.expects(:update_app).never

        [ 2.9, 1.5, Float::INFINITY, Float::NAN, "2.9" ].each do |instances|
          error = assert_raises(Integrations::Error) { call(:scale_app, "resource" => "shop", "component" => "web", "instances" => instances) }
          assert_equal "instances must be a whole number, 1 or more.", error.message, instances.inspect
        end
      end

      test "a change the token may not make says which scope to give it, and a Droplet reboots" do
        DigitaloceanApi.any_instance.stubs(:restart).raises(DigitaloceanApi::Error, "DigitalOcean answered 403: You do not have access for the attempted action.")

        assert_match "app:update", assert_raises(Integrations::Error) { call(:restart_app, "resource" => "shop") }.message
        assert_raises(Integrations::Error) { call(:restart_app, "resource" => "shop", "component" => "nope") }

        DigitaloceanApi.any_instance.expects(:droplet_action).with("3164494", "reboot").returns("action" => { "id" => 7, "status" => "in-progress" })
        assert_match "bastion is rebooting, action 7 in-progress.", call(:reboot_droplet, "resource" => "bastion")
        assert_raises(Integrations::Error) { call(:reboot_droplet, "resource" => "shop") }
      end

      test "the map holds the team's apps, Droplets and databases, the domains an app serves and the repository it builds from" do
        snapshot = @pack.map_of(@row)
        found = snapshot.resources.index_by(&:external_id)

        assert_equal ResourceMap::KIND_SERVICE, found[APP_ID].kind
        assert_equal "Acme", found[APP_ID].account
        assert_equal "abc1234567890def", found[APP_ID].details[ResourceMap::DEPLOYED_COMMIT]
        assert_equal ResourceMap::KIND_VIRTUAL_MACHINE, found["3164494"].kind
        assert_equal "mysql", found["db-1"].details["engine"]
        relations = snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
        assert_includes relations, [ "shop.acme.dev", ResourceMap::RELATION_SERVED_BY, APP_ID ]
        assert_includes relations, [ "shop-abc.ondigitalocean.app", ResourceMap::RELATION_SERVED_BY, APP_ID ]
        assert_includes relations, [ APP_ID, ResourceMap::RELATION_BUILT_FROM, "acme/shop" ]
      end

      test "an app's settings are read in memory, a bound database is a declared link, a secret is a name, and a database's address is digested" do
        spec = SPEC.deep_dup.merge(
          "envs" => [ { "key" => "REDIS_URL", "value" => "rediss://default:kv-pass@cache.example.com:25061", "type" => "GENERAL" },
                      { "key" => "LOG_LEVEL", "value" => "info" } ],
          "databases" => [ { "name" => "db", "engine" => "PG", "cluster_name" => "orders", "production" => true },
                           { "name" => "dev", "engine" => "PG" } ]
        )
        spec["services"].first["envs"] += [ { "key" => "ORDERS_URL", "value" => "${db.DATABASE_URL}", "scope" => "RUN_TIME" },
                                            { "key" => "PGHOST", "value" => "${db.HOSTNAME}" } ]
        DigitaloceanApi.any_instance.stubs(:apps).returns(listed(APP.merge("spec" => spec)))
        connection = { "host" => "orders-do-user-1-0.b.db.ondigitalocean.com", "port" => 25_060, "password" => "pg-pass",
                       "uri" => "postgresql://doadmin:pg-pass@orders-do-user-1-0.b.db.ondigitalocean.com:25060/defaultdb" }
        DigitaloceanApi.any_instance.stubs(:databases).returns(listed({ "id" => "db-9", "name" => "orders", "engine" => "pg", "connection" => connection,
                                                                    "private_connection" => connection.merge("host" => "private-orders.b.db.ondigitalocean.com") }))

        snapshot = @pack.map_of(@row)

        uses = snapshot.uses.index_by(&:variable)
        assert_equal %w[DATABASE_URL REDIS_URL], uses.keys.sort
        assert_nil uses["DATABASE_URL"].fingerprint
        assert_equal 25_061, uses["REDIS_URL"].port
        link = snapshot.links.find { |each| each.relation == ResourceMap::RELATION_USES }
        assert_equal [ APP_ID, "db-9", %w[ORDERS_URL PGHOST] ], [ link.from.last, link.to.last, link.variables ]
        assert_equal 1, snapshot.links.count { |each| each.relation == ResourceMap::RELATION_USES }
        assert_equal 4, snapshot.endpoints.size
        assert_no_setting_values(snapshot, "kv-pass", "cache.example.com", "hunter2", "pg-pass", connection["host"], connection["uri"])

        ResourceMap.record!(@row, snapshot)
        assert_equal %w[ORDERS_URL PGHOST], ResourceMap::Link.find_by!(workspace: @workspace, origin: ResourceMap::ORIGIN_DECLARED, relation: ResourceMap::RELATION_USES).variables
        assert_no_setting_values(snapshot, "kv-pass", "hunter2", "pg-pass", connection["host"])
      end

      test "an app counts the instances its services and workers run, and one with a component that scales on its own counts none" do
        fixed = SPEC.deep_dup.merge("workers" => [ { "name" => "jobs", "instance_count" => 3 }, { "name" => "mailer" } ])
        DigitaloceanApi.any_instance.stubs(:apps).returns(listed(APP.merge("spec" => fixed)))
        assert_equal 6, @pack.map_of(@row).resources.find { |resource| resource.external_id == APP_ID }.details[ResourceMap::INSTANCES]

        DigitaloceanApi.any_instance.stubs(:apps).returns(listed(APP))
        assert_not @pack.map_of(@row).resources.find { |resource| resource.external_id == APP_ID }.details.key?(ResourceMap::INSTANCES)
      end

      test "a Droplet's and a database's tags are kept as keys alone, since DigitalOcean's tags carry no value" do
        DigitaloceanApi.any_instance.stubs(:droplets).returns(Pages::Read.new(items: [ { "id" => 1, "name" => "one", "tags" => %w[web prod] } ], complete: true))
        DigitaloceanApi.any_instance.stubs(:databases).returns(Pages::Read.new(items: [ { "id" => "db-2", "name" => "orders", "engine" => "pg" } ], complete: true))

        found = @pack.map_of(@row).resources.index_by(&:external_id)

        assert_equal({ "web" => nil, "prod" => nil }, found["1"].details[ResourceMap::TAGS])
        assert_not found["db-2"].details.key?(ResourceMap::TAGS)
      end

      test "a list read only in part is a gap, and the kinds it holds are not taken as gone" do
        DigitaloceanApi.any_instance.stubs(:droplets).returns(Pages::Read.new(items: [ { "id" => 1, "name" => "one" } ], complete: false))

        snapshot = @pack.map_of(@row)

        assert_includes snapshot.unread_kinds, ResourceMap::KIND_VIRTUAL_MACHINE
        assert_equal [ ResourceMap::Gap.new(text: "Only the first 1 Droplets were read.", kinds: [ ResourceMap::KIND_VIRTUAL_MACHINE ]) ], snapshot.gaps
      end

      test "a list cut short says so, a resource past it is read by its id, and one not found is not said to be missing" do
        DigitaloceanApi.any_instance.stubs(:droplets).returns(Pages::Read.new(items: [ { "id" => 1, "name" => "one", "status" => "active" } ], complete: false))

        assert_match "Only the first 1 Droplets were read.", call(:list_resources)

        DigitaloceanApi.any_instance.stubs(:droplet).with("777").returns("id" => 777, "name" => "far", "status" => "active")
        assert_match "far, Droplet 777, active", call(:describe_resource, "resource" => "777")

        DigitaloceanApi.any_instance.stubs(:droplet).with("nowhere").raises(DigitaloceanApi::Error, "DigitalOcean answered 404: not found")
        error = assert_raises(Integrations::Error) { call(:describe_resource, "resource" => "nowhere") }
        assert_equal "No app, Droplet or database called nowhere among the first 1 Droplets read from this DigitalOcean account. Name it by its id.", error.message
      end

      test "a resource is found by id first, and two of one name are refused with each one's id" do
        DigitaloceanApi.any_instance.stubs(:droplets).returns(listed({ "id" => 1, "name" => "shop", "status" => "active" }, { "id" => 2, "name" => "worker" }))

        error = assert_raises(Integrations::Error) { call(:describe_resource, "resource" => "shop") }
        assert_equal "More than one DigitalOcean resource is called shop: App Platform app #{APP_ID}, Droplet 1. Name it by its id.", error.message
        DigitaloceanApi.any_instance.stubs(:droplet).returns("id" => 1, "name" => "shop", "status" => "active")
        assert_match "shop, Droplet 1", call(:describe_resource, "resource" => "1")
      end

      test "a list the token may not read is a gap, and the kinds it holds are not taken as gone" do
        DigitaloceanApi.any_instance.stubs(:databases).raises(DigitaloceanApi::Error, "DigitalOcean answered 403: forbidden")

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_DATABASE ], snapshot.unread_kinds
        assert_equal "The managed databases could not be read: DigitalOcean answered 403: forbidden.", snapshot.gaps.sole.text
      end

      test "an app list the token may not read holds back the domains and repositories apps put on the map too" do
        DigitaloceanApi.any_instance.stubs(:apps).raises(DigitaloceanApi::Error, "DigitalOcean answered 403: forbidden")

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ], snapshot.unread_kinds
      end

      test "baselines average an app's instances, and a database other than MySQL has none" do
        app = resource(ResourceMap::KIND_SERVICE, APP_ID, "shop")
        pg = resource(ResourceMap::KIND_DATABASE, "db-2", "pg", "engine" => "pg")
        DigitaloceanApi.any_instance.stubs(:metrics).returns([ { "metric" => { "app_component_instance" => "web-0" }, "values" => [ [ 100, "10" ] ] },
                                                               { "metric" => { "app_component_instance" => "web-1" }, "values" => [ [ 100, "30" ] ] } ])

        found = @pack.baselines_of(@row, [ app, pg ], 7.days.ago..Time.current)

        assert_equal [ [ "cpu", 20.0 ], [ "memory", 20.0 ] ], found.map { |reading| [ reading.metric, reading.points.sole.last ] }
        DigitaloceanApi.any_instance.stubs(:metrics).raises(DigitaloceanApi::Error.new("DigitalOcean answered 429").extend(Integrations::RateLimited))
        assert_raises(Integrations::RateLimited) { @pack.baselines_of(@row, [ app ], 7.days.ago..Time.current) }
      end

      test "deploy history ends a deployment when its last step ended, or when its phase last changed" do
        DigitaloceanApi.any_instance.stubs(:deployments).returns([
          { "id" => "dep-2", "phase" => "ACTIVE", "created_at" => "2026-10-01T09:00:00Z", "phase_last_updated_at" => "2026-10-01T09:10:00Z",
            "progress" => { "steps" => [ { "name" => "build", "ended_at" => "2026-10-01T09:04:00Z" }, { "name" => "deploy", "ended_at" => "2026-10-01T09:06:00Z" } ] } },
          { "id" => "dep-1", "phase" => "ERROR", "created_at" => "2026-10-01T08:00:00Z", "phase_last_updated_at" => "2026-10-01T08:02:00Z" },
          { "id" => "dep-3", "phase" => "BUILDING", "created_at" => "2026-10-01T10:00:00Z" }
        ])

        runs = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => APP_ID }))

        assert_equal [ [ "dep-3", "running", nil ], [ "dep-2", "succeeded", 360 ], [ "dep-1", "failed", 120 ] ], runs.map { |run| [ run.id, run.status, run.seconds ] }
        assert_equal "https://cloud.digitalocean.com/apps/#{APP_ID}/deployments/dep-2", runs.second.url
      end

      # The shape of apps_get_deployment and apps_deployment_progress_step in digitalocean/openapi, with a build step whose
      # child steps run per component and a deploy step that never started.
      DEPLOYMENT = {
        "id" => "dep-9", "phase" => "ERROR", "cause" => "commit 9f8e7d6 pushed to github/acme/shop", "created_at" => "2026-10-01T06:00:00Z",
        "phase_last_updated_at" => "2026-10-01T06:05:00Z",
        "progress" => {
          "error_steps" => 1, "total_steps" => 3,
          "steps" => [
            { "name" => "build", "status" => "ERROR", "started_at" => "2026-10-01T06:00:10Z", "ended_at" => "2026-10-01T06:04:00Z",
              "steps" => [
                { "name" => "initialize", "status" => "SUCCESS", "started_at" => "2026-10-01T06:00:10Z", "ended_at" => "2026-10-01T06:00:20Z" },
                { "name" => "components", "status" => "ERROR",
                  "steps" => [
                    { "name" => "web", "component_name" => "web", "message_base" => "Building service", "status" => "ERROR",
                      "started_at" => "2026-10-01T06:00:20Z", "ended_at" => "2026-10-01T06:04:00Z",
                      "reason" => { "code" => "BuildJobExitNonZero", "message" => "Your build job failed because it returned a non-zero exit code." } },
                    { "name" => "jobs", "component_name" => "jobs", "message_base" => "Building worker", "status" => "SUCCESS",
                      "started_at" => "2026-10-01T06:00:20Z", "ended_at" => "2026-10-01T06:02:00Z" }
                  ] }
              ] },
            { "name" => "deploy", "status" => "PENDING", "steps" => [] }
          ]
        }
      }.freeze

      test "one deployment asked by its id is read on its own, with each component it built and the log of that deployment" do
        DigitaloceanApi.any_instance.expects(:deployment).with(APP_ID, "dep-9").returns(DEPLOYMENT.deep_dup)
        DigitaloceanApi.any_instance.expects(:deployments).never

        run = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => APP_ID, "run" => "dep-9" })).sole

        assert_equal [ "dep-9", "failed", 240 ], [ run.id, run.status, run.seconds ]
        assert_equal "https://cloud.digitalocean.com/apps/#{APP_ID}/deployments/dep-9", run.url
        assert_equal [ [ "Building service web", "failed" ], [ "Building worker jobs", "succeeded" ], [ "deploy", "queued" ] ],
                     run.parts.map { |part| [ part.name, part.status ] }
        failed = run.first_failed_part
        assert_equal "Your build job failed because it returned a non-zero exit code.", failed.detail
        assert_equal 220, failed.seconds
        assert_equal({ Capabilities::History::LOG_TOOL => "app_logs",
                       Capabilities::History::LOG_ARGUMENTS => { "resource" => APP_ID, "deployment" => "dep-9", "type" => "BUILD", "component" => "web" } }, failed.log)
        assert_equal({ "resource" => APP_ID, "deployment" => "dep-9", "type" => "DEPLOY" }, run.parts.last.log[Capabilities::History::LOG_ARGUMENTS])
      end

      test "a deployment the app does not hold is said in words" do
        DigitaloceanApi.any_instance.stubs(:deployment).raises(DigitaloceanApi::NotFound, "DigitalOcean answered 404: not found")
        DigitaloceanApi.any_instance.stubs(:job_invocation).raises(DigitaloceanApi::NotFound, "DigitalOcean answered 404: not found")

        error = assert_raises(NativePack::Error) { call(:deploy_history, "resource" => APP_ID, "run" => "dep-0") }

        assert_equal "shop has no deployment or job run dep-0. deploy_history lists its recent ones.", error.message
      end

      test "the logs of one deployment are read whole, however old, and link to that deployment" do
        DigitaloceanApi.any_instance.expects(:logs).with(APP_ID, type: "BUILD", component: "web", deployment: "dep-9").returns(historic: [ "https://logs.example/build.log" ], live: nil)
        DigitaloceanApi.any_instance.stubs(:log_file).returns(<<~LOG)
          web 2026-09-01T06:01:00Z npm ci
          web 2026-09-01T06:03:59Z npm ERR! missing script: build
        LOG

        text = call(:app_logs, "resource" => "shop", "deployment" => "dep-9", "component" => "web", "type" => "BUILD")

        assert_match "BUILD logs of shop (web) deployment dep-9", text
        assert_match "missing script: build", text
        assert_match "npm ci", text
        assert_match "https://cloud.digitalocean.com/apps/#{APP_ID}/deployments/dep-9", text
        assert_no_match "logs.example", text
      end

      test "billing reads the month so far by product and the months before, and links the billing page" do
        DigitaloceanApi.any_instance.stubs(:balance).returns("month_to_date_usage" => "412.10", "account_balance" => "0.00", "generated_at" => "2026-10-10T08:00:00Z")
        DigitaloceanApi.any_instance.stubs(:invoices).with(limit: 3).returns(
          "invoice_preview" => { "invoice_uuid" => "preview-1", "amount" => "412.10", "invoice_period" => "2026-10" },
          "invoices" => [ { "invoice_uuid" => "inv-9", "amount" => "640.00", "invoice_period" => "2026-09" },
                          { "invoice_uuid" => "inv-8", "amount" => "601.55", "invoice_period" => "2026-08" } ]
        )
        DigitaloceanApi.any_instance.stubs(:invoice_summary).with("preview-1").returns(
          "product_charges" => { "items" => [ { "name" => "Droplets", "amount" => "120.00" }, { "name" => "Managed Databases", "amount" => "290.10" } ] }
        )

        result = @pack.call("billing", environment_row: @row, arguments: {})
        text = result["content"].map { |part| part["text"] }.join("\n")

        assert_match "Used this month so far: $412.10", text
        assert_match "By product this month:\n- Managed Databases: $290.10\n- Droplets: $120.00", text
        assert_match "- 2026-09: $640.00\n- 2026-08: $601.55", text
        assert Digitalocean.tool_definitions.find { |tool| tool.name == "billing" }.read_only
      end

      test "billing refused for want of the scope says which scope to give" do
        DigitaloceanApi.any_instance.stubs(:balance).raises(DigitaloceanApi::Error, "DigitalOcean answered 403: You are not authorized")

        refused = assert_raises(Integrations::NativePack::Error) { @pack.call("billing", environment_row: @row, arguments: {}) }

        assert_match "The token needs the billing:read scope", refused.message
      end

      private

      def resource(kind, id, name, details = {})
        ResourceMap::Resource.create!(workspace: @workspace, provider: Digitalocean::PROVIDER_KEY, account: "Acme", kind: kind, external_id: id, name: name,
                                      integration_environment: @row, details: details, first_seen_at: Time.current, last_seen_at: Time.current)
      end

      def listed(*items) = Pages::Read.new(items: items, complete: true)

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
