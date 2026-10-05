require "test_helper"

module Integrations
  module Packs
    class RailwayTest < ActiveSupport::TestCase
      PAGE = "https://railway.com/project/prj-1/service/svc-web?environmentId=env-prod".freeze
      PROJECT = { "id" => "prj-1", "name" => "shop", "environments" => { "edges" => [ { "node" => { "id" => "env-prod", "name" => "production" } } ] } }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway")
        @row = @integration.integration_environments.create!
        Railway.store_credentials!(@row, Railway::API_TOKEN => " rw-token ")
        @row.store_fields!(Railway::PROJECT => "prj-1", Railway::ENVIRONMENT => "Production")
        @pack = Railway.new(@integration)
        RailwayApi.any_instance.stubs(:project).with("prj-1").returns(PROJECT)
        RailwayApi.any_instance.stubs(:service_instances).with("prj-1", "env-prod").returns(Integrations::Pages::Read.new(items: [
          { "serviceId" => "svc-web", "serviceName" => "web", "numReplicas" => 2, "region" => "us-west2", "startCommand" => "bin/start",
            "restartPolicyType" => "ON_FAILURE", "restartPolicyMaxRetries" => 10, "source" => { "repo" => "acme/shop" },
            "latestDeployment" => { "id" => "dep-2", "status" => "CRASHED", "createdAt" => "2026-10-01T09:00:00Z", "canRollback" => true,
                                    "meta" => { "commitHash" => "c4e4267d46e638ac", "serviceManifest" => { "deploy" => { "multiRegionConfig" => { "us-west2" => { "numReplicas" => 2 } } } } },
                                    "instances" => [ { "status" => "CRASHED" }, { "status" => "RUNNING" } ] },
            "domains" => { "serviceDomains" => [ { "domain" => "web.up.railway.app", "targetPort" => 8080 } ], "customDomains" => [ { "domain" => "shop.acme.dev" } ] } },
          { "serviceId" => "svc-db", "serviceName" => "Postgres", "source" => { "image" => "ghcr.io/railwayapp-templates/postgres-ssl:16" },
            "restartPolicyType" => "ALWAYS", "latestDeployment" => { "id" => "dep-db", "status" => "SUCCESS" } },
          { "serviceId" => "svc-cron", "serviceName" => "nightly", "cronSchedule" => "0 3 * * *", "restartPolicyType" => "NEVER" }
        ], complete: true))
      end

      test "the credentials are stored trimmed, and only the restart, rollback and scale change anything" do
        assert_equal "rw-token", ConnectionSettings.of(@row.reload).credential(Railway::API_TOKEN)
        assert_equal %w[restart_deployment rollback_deployment scale_service], Railway.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a wrong token, or an environment the project does not have, is said on the form before anything is saved" do
        assert_nil Railway.credential_refusal({ Railway::API_TOKEN => "t" }, fields: { Railway::PROJECT => "prj-1", Railway::ENVIRONMENT => "env-prod" })
        assert_equal "The project has no environment called staging. It has production.",
                     Railway.credential_refusal({ Railway::API_TOKEN => "t" }, fields: { Railway::PROJECT => "prj-1", Railway::ENVIRONMENT => "staging" })
        RailwayApi.any_instance.stubs(:project).raises(RailwayApi::Error, "Railway refused this: Not Authorized")
        assert_equal "Railway refused this token or project: Not Authorized.",
                     Railway.credential_refusal({ Railway::API_TOKEN => "t" }, fields: { Railway::PROJECT => "prj-1", Railway::ENVIRONMENT => "production" })
      end

      test "resources are told apart as the CLI does, with their latest deployment's status" do
        text = call(:list_resources)

        assert_match "web (svc-web), service, crashed", text
        assert_match "Postgres (svc-db), database, success", text
        assert_match "nightly (svc-cron), cron job, never deployed", text
        assert text.end_with?("https://railway.com/project/prj-1?environmentId=env-prod")
      end

      test "app logs are the environment's filtered to the service, with text and exclude in Railway's syntax, newest first" do
        RailwayApi.any_instance.expects(:environment_logs).with do |variables|
          variables["environmentId"] == "env-prod" && variables["filter"] == "@service:svc-web AND \"timeout\" AND -\"healthz\"" &&
            variables["afterLimit"].zero? && variables["beforeLimit"] == 50
        end.returns([
          { "timestamp" => 10.minutes.ago.utc.iso8601, "message" => "older", "severity" => "info", "tags" => { "deploymentInstanceId" => "i-1" } },
          { "timestamp" => 5.minutes.ago.utc.iso8601, "message" => "upstream timeout", "severity" => "error", "tags" => { "deploymentInstanceId" => "i-1" } }
        ])

        text = call(:search_logs, "resource" => "web", "text" => "timeout", "exclude" => "healthz", "limit" => 50)

        assert_match(/2 log lines.*\n.* i-1 error: upstream timeout\n.* i-1 info: older/, text)
        assert text.end_with?(PAGE)
      end

      test "HTTP logs read the latest deployment's requests with status, duration and why the app did not answer" do
        RailwayApi.any_instance.expects(:http_logs).with(has_entries("deploymentId" => "dep-2", "beforeLimit" => 200)).returns([
          { "timestamp" => 1.minute.ago.utc.iso8601, "method" => "GET", "host" => "shop.acme.dev", "path" => "/cart", "httpStatus" => 502,
            "totalDuration" => 15_000, "responseDetails" => "failed to forward request to upstream", "deploymentInstanceId" => "i-1" }
        ])

        assert_match "GET shop.acme.dev/cart 502 15000ms failed to forward request to upstream", call(:search_logs, "resource" => "web", "type" => "http")
      end

      test "metrics read Railway's measurements and its requests by status, 5xx added up and counted per minute" do
        RailwayApi.any_instance.expects(:metrics).with(has_entries("serviceId" => "svc-web", "measurements" => [ "CPU_USAGE" ])).returns([
          { "measurement" => "CPU_USAGE", "values" => [ { "ts" => 1_790_000_000, "value" => 0.4 } ] }
        ])
        RailwayApi.any_instance.expects(:http_by_status).returns([
          { "statusCode" => 502, "samples" => [ { "ts" => 1_790_000_000, "value" => 6 } ] },
          { "statusCode" => 503, "samples" => [ { "ts" => 1_790_000_000, "value" => 4 } ] },
          { "statusCode" => 200, "samples" => [ { "ts" => 1_790_000_000, "value" => 600 } ] }
        ])

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => %w[cpu http_5xx], "minutes" => 60 })

        charts = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS)
        assert_equal [ "CPU of web", "5xx responses of web" ], charts.map { |chart| chart["title"] }
        assert_equal [ "vCPU", "per minute" ], charts.map { |chart| chart["unit"] }
        assert_equal 10.0, charts.last["series"].sole["points"].sole.last
      end

      test "a service's status says how its replicas stand, what it runs and how it restarts" do
        text = call(:describe_resource, "resource" => "web")

        assert_match "Latest deployment: 2026-10-01T09:00:00Z, deployment dep-2, CRASHED, c4e4267d46e6, can be rolled back to", text
        assert_match "Replicas now: 1 crashed, 1 running", text
        assert_match "Runs acme/shop, start command bin/start", text
        assert_match "Health check: none", text
        assert_match "Restart policy: ON_FAILURE, at most 10 times", text
        assert_match "Domains: web.up.railway.app to port 8080, shop.acme.dev", text
      end

      test "a restart reaches the latest deployment, and a rollback only one Railway can still roll back to" do
        RailwayApi.any_instance.expects(:restart).with("dep-2").returns(true)
        assert_match "Railway is restarting deployment dep-2 of web", call(:restart_deployment, "resource" => "web")

        RailwayApi.any_instance.stubs(:deployments).returns([ { "id" => "dep-1", "canRollback" => true }, { "id" => "dep-0", "canRollback" => false } ])
        RailwayApi.any_instance.expects(:rollback).with("dep-1").returns(true)
        assert_match "rolling web back to deployment dep-1", call(:rollback_deployment, "resource" => "web", "deployment" => "dep-1")
        assert_match "no longer keeps its image", assert_raises(NativePack::Error) { call(:rollback_deployment, "resource" => "web", "deployment" => "dep-0") }.message
        assert_match "not among the latest", assert_raises(NativePack::Error) { call(:rollback_deployment, "resource" => "web", "deployment" => "dep-9") }.message
      end

      test "a scale commits the region's replicas as the CLI does, and one that cannot say where the replicas go is refused" do
        RailwayApi.any_instance.expects(:patch_commit).with(
          "env-prod", { "services" => { "svc-web" => { "deploy" => { "multiRegionConfig" => { "us-west2" => { "numReplicas" => 4 } } } } } },
          "Scale service web to 4 replicas from Firefight"
        ).returns("commit-1")
        assert_match "Railway is scaling web to 4 replicas in us-west2 from 2.", call(:scale_service, "resource" => "web", "instances" => "4")

        assert_match "from 1 to 50", assert_raises(NativePack::Error) { call(:scale_service, "resource" => "web", "instances" => 0) }.message
        @pack = Railway.new(@integration)
        RailwayApi.any_instance.stubs(:service_instances).returns(Integrations::Pages::Read.new(items: [
          { "serviceId" => "svc-web", "serviceName" => "web", "latestDeployment" => { "id" => "dep-2", "meta" => { "serviceManifest" => { "deploy" => {
            "multiRegionConfig" => { "us-west2" => { "numReplicas" => 2 }, "europe-west4-drams3a" => { "numReplicas" => 1 } } } } } } }
        ], complete: true))
        assert_match "runs in us-west2, europe-west4-drams3a", assert_raises(NativePack::Error) { call(:scale_service, "resource" => "web", "instances" => 3) }.message
      end

      test "the environment goes on the map with each service's kind, repository and domains" do
        snapshot = @pack.map_of(@row)

        found = snapshot.resources.index_by(&:external_id)
        assert_equal [ ResourceMap::KIND_SERVICE, "crashed", PAGE, "c4e4267d46e638ac", "prj-1/env-prod" ],
                     [ found["svc-web"].kind, found["svc-web"].status, found["svc-web"].url, found["svc-web"].details[ResourceMap::DEPLOYED_COMMIT], found["svc-web"].account ]
        assert_equal [ ResourceMap::KIND_DATABASE, "Postgres database" ], [ found["svc-db"].kind, found["svc-db"].details["type"] ]
        assert_equal ResourceMap::KIND_JOB, found["svc-cron"].kind
        assert_equal [ [ "svc-web", ResourceMap::RELATION_BUILT_FROM, "acme/shop" ], [ "web.up.railway.app", ResourceMap::RELATION_SERVED_BY, "svc-web" ],
                       [ "shop.acme.dev", ResourceMap::RELATION_SERVED_BY, "svc-web" ] ],
                     snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
      end

      test "a service list cut short holds back every kind it puts on the map, its domains and repositories with it" do
        RailwayApi.any_instance.stubs(:service_instances).returns(Integrations::Pages::Read.new(items: [], complete: false))

        snapshot = @pack.map_of(@row)

        assert_includes snapshot.unread_kinds, ResourceMap::KIND_DOMAIN
        assert_includes snapshot.unread_kinds, ResourceMap::KIND_REPOSITORY
      end

      test "a week of cpu and memory per service, and being asked to slow down stops the read" do
        web = ResourceMap::Resource.new(provider: "railway", account: "prj-1/env-prod", kind: ResourceMap::KIND_SERVICE, external_id: "svc-web", name: "web")
        repository = ResourceMap::Resource.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/shop", name: "acme/shop")
        RailwayApi.any_instance.expects(:metrics).with(has_entries("serviceId" => "svc-web", "sampleRateSeconds" => 3600)).returns([
          { "measurement" => "MEMORY_USAGE_GB", "values" => [ { "ts" => 1_790_000_000, "value" => 0.5 }, { "ts" => 1_790_003_600, "value" => 0.7 } ] }
        ])

        found = @pack.baselines_of(@row, [ web, repository ], 7.days.ago..Time.current)

        assert_equal [ [ "memory", "GB", [ 0.5, 0.7 ] ] ], found.map { |each| [ each.metric, each.unit, each.points.map(&:last) ] }
        RailwayApi.any_instance.stubs(:metrics).raises(RailwayApi::Error.new("Railway answered 429: slow down").extend(Integrations::RateLimited))
        assert_raises(Integrations::RateLimited) { @pack.baselines_of(@row, [ web ], 7.days.ago..Time.current) }
      end

      test "the health check finds the environment in the project" do
        @pack.check_health!(@row)

        RailwayApi.any_instance.stubs(:project).raises(RailwayApi::Error, "Railway refused this: Not Authorized")
        assert_raises(NativePack::Error) { Railway.new(@integration).check_health!(@row) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
