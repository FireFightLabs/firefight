require "test_helper"

module Integrations
  module Packs
    class RailwayDeploymentsTest < ActiveSupport::TestCase
      PROJECT = { "id" => "prj-1", "name" => "shop", "environments" => { "edges" => [ { "node" => { "id" => "env-prod", "name" => "production" } } ] } }.freeze
      PR_PAGE = "https://railway.com/project/prj-1/service/svc-web?environmentId=env-pr-12".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway")
        @row = @integration.integration_environments.create!
        Railway.store_credentials!(@row, Railway::API_TOKEN => "rw-token")
        @row.store_fields!(Railway::PROJECT => "prj-1", Railway::ENVIRONMENT => "production")
        RailwayApi.any_instance.stubs(:project).with("prj-1").returns(PROJECT)
        RailwayApi.any_instance.stubs(:environments).with("prj-1").returns(Integrations::Pages::Read.new(items: [
          { "id" => "env-prod", "name" => "production", "isEphemeral" => false, "meta" => {} },
          { "id" => "env-pr-12", "name" => "shop-pr-12", "isEphemeral" => true, "meta" => { "prNumber" => 12, "prTitle" => "Faster checkout" } }
        ], complete: true))
        stub_instances("env-prod", latest: { "id" => "dep-2", "status" => "SUCCESS" })
      end

      test "the project's other environments are listed with the pull request each is for, and a call naming one reads it alone" do
        text = call(:list_resources)
        assert_match "Other environments of the project, each read by passing it as environment:\nshop-pr-12 (env-pr-12), PR environment for pull request #12 Faster checkout", text

        stub_instances("env-pr-12", latest: { "id" => "dep-pr", "status" => "BUILDING" })
        RailwayApi.any_instance.expects(:deployments).with("prj-1", "env-pr-12", "svc-web", limit: 20).returns([])
        result = @pack.call("list_deployments", environment_row: @row, arguments: { "resource" => "web", "environment" => "shop-pr-12" })
        assert result["content"].sole["text"].end_with?(PR_PAGE)

        error = assert_raises(NativePack::Error) { call(:describe_resource, "resource" => "web", "environment" => "staging") }
        assert_equal "Project prj-1 has no environment called staging. It has production, shop-pr-12.", error.message
      end

      test "a deployment still building is cancelled, and one that already finished is refused in words" do
        own_deployment("dep-3", "status" => "BUILDING")
        RailwayApi.any_instance.expects(:cancel).with("dep-3").returns(true)
        assert_match "Railway is cancelling deployment dep-3 of web, which was building. The deployment serving before it keeps serving.",
                     call(:cancel_deployment, "resource" => "web", "deployment" => "dep-3")

        own_deployment("dep-2", "status" => "SUCCESS")
        error = assert_raises(NativePack::Error) { call(:cancel_deployment, "resource" => "web", "deployment" => "dep-2") }
        assert_equal "Deployment dep-2 of web is success, so there is nothing to cancel.", error.message
      end

      test "a deployment of another service or environment is never changed" do
        RailwayApi.any_instance.stubs(:deployment).with("dep-other").returns("id" => "dep-other", "status" => "BUILDING", "serviceId" => "svc-api", "environmentId" => "env-prod")
        RailwayApi.any_instance.expects(:cancel).never

        error = assert_raises(NativePack::Error) { call(:cancel_deployment, "resource" => "web", "deployment" => "dep-other") }
        assert_match "web has no deployment dep-other in this environment", error.message
      end

      test "stopping takes the latest deployment unless one is named, and says the service serves nothing until restarted" do
        own_deployment("dep-2", "status" => "SUCCESS")
        RailwayApi.any_instance.expects(:stop).with("dep-2").returns(true)

        assert_match "Railway is stopping deployment dep-2 of web. It serves nothing until restart_deployment starts it again or a new deployment goes live.",
                     call(:stop_deployment, "resource" => "web")
      end

      test "a redeploy answers the new deployment to follow, and one Railway cannot redeploy is refused" do
        own_deployment("dep-2", "status" => "SUCCESS", "canRedeploy" => true)
        RailwayApi.any_instance.expects(:redeploy).with("dep-2").returns("id" => "dep-5", "status" => "QUEUED")
        assert_match "Railway is redeploying web from deployment dep-2, as deployment dep-5, building the same code with the same settings. " \
                     "Follow it with deploy_history and run dep-5.", call(:redeploy_deployment, "resource" => "web")

        own_deployment("dep-2", "status" => "REMOVED", "canRedeploy" => false)
        assert_raises(NativePack::Error) { call(:redeploy_deployment, "resource" => "web") }
      end

      test "only a deployment waiting for approval is approved" do
        own_deployment("dep-6", "status" => "NEEDS_APPROVAL")
        RailwayApi.any_instance.expects(:approve).with("dep-6").returns(true)
        assert_match "Approved deployment dep-6 of web, so Railway builds and deploys it.", call(:approve_deployment, "resource" => "web", "deployment" => "dep-6")

        own_deployment("dep-2", "status" => "SUCCESS")
        error = assert_raises(NativePack::Error) { call(:approve_deployment, "resource" => "web", "deployment" => "dep-2") }
        assert_equal "Deployment dep-2 of web is success, not waiting for approval.", error.message
      end

      test "whoever made the deployment a cancel or stop would end is its owner, and one Railway started names nobody" do
        own_deployment("dep-3", "status" => "BUILDING", "creator" => { "name" => "Ada", "email" => "ada@example.com" })
        owner = @pack.owner_of("cancel_deployment", environment_row: @row, arguments: { "resource" => "web", "deployment" => "dep-3" })
        assert_equal [ "Ada", "ada@example.com", Owner::ROLE_STARTED, "deployment dep-3 of web" ], [ owner.name, owner.email, owner.role, owner.what ]

        own_deployment("dep-2", "status" => "SUCCESS", "creator" => nil)
        assert_nil Railway.new(@integration).owner_of("stop_deployment", environment_row: @row, arguments: { "resource" => "web" })
        assert_nil Railway.new(@integration).owner_of("restart_deployment", environment_row: @row, arguments: { "resource" => "web" })
      end

      test "a removed deployment whose steps switched traffic to it went live, and one stopped before that was cancelled" do
        own_deployment("dep-4", "status" => "REMOVED", "canRollback" => false, "createdAt" => "2026-10-01T10:00:00Z", "updatedAt" => "2026-10-01T10:09:00Z")
        RailwayApi.any_instance.stubs(:deployment_events).with("dep-4", limit: 50).returns([
          { "id" => "ev-1", "step" => "BUILD_IMAGE", "createdAt" => "2026-10-01T10:00:00Z", "completedAt" => "2026-10-01T10:02:00Z", "payload" => {} },
          { "id" => "ev-2", "step" => "CONFIGURE_NETWORK", "createdAt" => "2026-10-01T10:03:00Z", "completedAt" => "2026-10-01T10:03:10Z", "payload" => {} }
        ])
        run = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "web", "run" => "dep-4" })).sole
        assert_equal [ Capabilities::History::SUCCEEDED, nil ], [ run.status, run.finished_at ]

        RailwayApi.any_instance.stubs(:deployment_events).with("dep-4", limit: 50).returns([
          { "id" => "ev-1", "step" => "BUILD_IMAGE", "createdAt" => "2026-10-01T10:00:00Z", "payload" => {} }
        ])
        run = Capabilities::History.runs_of(Railway.new(@integration).call("deploy_history", environment_row: @row, arguments: { "resource" => "web", "run" => "dep-4" })).sole
        assert_equal [ Capabilities::History::CANCELLED, Time.zone.parse("2026-10-01T10:09:00Z") ], [ run.status, run.finished_at ]
      end

      test "latency is each percentile of the service's request durations, in milliseconds" do
        RailwayApi.any_instance.expects(:http_duration).with do |variables|
          variables["serviceId"] == "svc-web" && variables["environmentId"] == "env-prod" && variables["stepSeconds"] == 60
        end.returns([ { "ts" => 1_790_000_000, "p50" => 12.0, "p90" => 40.0, "p95" => 80.5, "p99" => 300.0 } ])

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => %w[latency_p95 latency_p99], "minutes" => 60 })
        charts = result[Telemetry::STRUCTURED]["charts"]

        assert_equal [ "Latency, 95th percentile of web", "Latency, 99th percentile of web" ], charts.map { |chart| chart["title"] }
        assert_equal [ "ms", 80.5 ], [ charts.first["unit"], charts.first["series"].sole["points"].sole.last ]
      end

      test "a cron job's runs are its executions, newest first, and one run is read with its log over the time it ran" do
        RailwayApi.any_instance.expects(:cron_runs).with("env-prod", "svc-cron", limit: 20).returns([
          { "id" => "run-2", "deploymentId" => "dep-c", "status" => "CRASHED", "createdAt" => "2026-10-12T00:01:53Z", "completedAt" => "2026-10-12T00:02:01Z" },
          { "id" => "run-1", "deploymentId" => "dep-c", "status" => "EXITED", "createdAt" => "2026-10-11T00:02:21Z", "completedAt" => "2026-10-11T00:02:29Z" },
          { "id" => "run-0", "deploymentId" => "dep-c", "status" => "SKIPPED", "createdAt" => "2026-10-10T00:00:00Z", "updatedAt" => "2026-10-10T00:00:01Z" }
        ])
        runs = Capabilities::History.runs_of(@pack.call("cron_runs", environment_row: @row, arguments: { "resource" => "nightly" }))

        assert_equal %w[failed succeeded cancelled], runs.map(&:status)
        assert_equal [ 8, 8, 1 ], runs.map(&:seconds)
        assert_equal "deployment dep-c, skipped because the run before it still ran", runs.last.detail

        RailwayApi.any_instance.unstub(:cron_runs)
        RailwayApi.any_instance.expects(:cron_runs).with("env-prod", "svc-cron", limit: 1000).returns([
          { "id" => "run-2", "deploymentId" => "dep-c", "status" => "CRASHED", "createdAt" => "2026-10-12T00:01:53Z", "completedAt" => "2026-10-12T00:02:01Z" }
        ])
        part = Capabilities::History.runs_of(Railway.new(@integration).call("cron_runs", environment_row: @row, arguments: { "resource" => "nightly", "run" => "run-2" })).sole.parts.sole
        assert_equal({ "tool" => "search_logs", "arguments" => { "resource" => "svc-cron", "type" => "app", "start" => "2026-10-12T00:01:53Z", "end" => "2026-10-12T00:03:01Z" } }, part.log)

        error = assert_raises(NativePack::Error) { Railway.new(@integration).call("cron_runs", environment_row: @row, arguments: { "resource" => "web" }) }
        assert_match "web has no cron schedule in this environment", error.message
      end

      test "traces are failed and slowest first, and one trace reads as a tree of its spans" do
        RailwayApi.any_instance.expects(:traces).with do |variables|
          variables["environmentId"] == "env-prod" && variables["serviceId"] == "svc-web" && variables["filter"] == "@duration:>500" && variables["limit"] == 20
        end.returns([
          { "traceId" => "a" * 32, "startedAt" => "2026-10-12T10:00:00Z", "durationMs" => 120.0, "rootSpanName" => "GET", "rootUrlPath" => "/", "spanCount" => 3, "errorCount" => 0, "serviceName" => "web" },
          { "traceId" => "b" * 32, "startedAt" => "2026-10-12T10:01:00Z", "durationMs" => 900.0, "rootSpanName" => "GET", "rootUrlPath" => "/cart", "spanCount" => 5, "errorCount" => 0, "serviceName" => "web" },
          { "traceId" => "c" * 32, "startedAt" => "2026-10-12T10:02:00Z", "durationMs" => 50.0, "rootSpanName" => "POST", "rootUrlPath" => "/pay", "spanCount" => 4, "errorCount" => 1, "serviceName" => "web" }
        ])
        text = call(:search_traces, "resource" => "web", "text" => "@duration:>500")
        assert_equal [ "c" * 32, "b" * 32, "a" * 32 ], text.scan(/trace (\h{32})/).flatten

        RailwayApi.any_instance.expects(:trace).with("env-prod", "c" * 32, max_spans: 200).returns([
          { "spanId" => "s1", "name" => "POST /pay", "component" => "edge", "serviceName" => "web", "durationMs" => 50.0, "statusCode" => "OK", "startedAt" => "1" },
          { "spanId" => "s2", "parentSpanId" => "s1", "name" => "charge", "component" => "service", "serviceName" => "web", "durationMs" => 40.0,
            "statusCode" => "ERROR", "statusMessage" => "card declined", "startedAt" => "2" }
        ])
        assert_match "- POST /pay (edge, web), 50.0ms\n  - charge (service, web), 40.0ms, error: card declined", call(:search_traces, "trace" => "c" * 32)
        assert_raises(NativePack::Error) { call(:search_traces, "trace" => "not-a-trace") }
      end

      private

      def stub_instances(environment_id, latest:)
        RailwayApi.any_instance.stubs(:service_instances).with("prj-1", environment_id).returns(Integrations::Pages::Read.new(items: [
          { "serviceId" => "svc-web", "serviceName" => "web", "restartPolicyType" => "ALWAYS", "latestDeployment" => latest },
          { "serviceId" => "svc-cron", "serviceName" => "nightly", "cronSchedule" => "0 0 * * *", "restartPolicyType" => "NEVER" }
        ], complete: true))
        @pack = Railway.new(@integration)
      end

      def own_deployment(id, fields)
        RailwayApi.any_instance.stubs(:deployment).with(id).returns({ "id" => id, "serviceId" => "svc-web", "environmentId" => "env-prod" }.merge(fields))
      end

      def call(tool, arguments = {}) = Array(Railway.new(@integration).call(tool.to_s, environment_row: @row, arguments: arguments)["content"]).sole["text"]
    end
  end
end
