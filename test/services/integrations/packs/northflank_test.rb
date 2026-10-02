require "test_helper"

module Integrations
  module Packs
    class NorthflankTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
        @row = @integration.integration_environments.create!
        Northflank.store_credentials!(@row, Northflank::API_TOKEN => " nf-token ", Northflank::PROJECT => "firefight")
        @pack = Northflank.new(@integration)
        NorthflankApi.any_instance.stubs(:services).returns([
          { "id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/firefight-labs/firefight/web",
            "status" => { "deployment" => { "status" => "COMPLETED" } } }
        ])
        NorthflankApi.any_instance.stubs(:addons).returns([
          { "id" => "db", "name" => "db", "spec" => { "type" => "postgresql" }, "status" => "running", "appId" => "/firefight-labs/firefight/db" }
        ])
      end

      test "the token and project are stored trimmed, and every tool only reads" do
        assert_equal "nf-token", @row.reload.credentials_hash[Northflank::API_TOKEN]
        assert Northflank.tool_definitions.all?(&:read_only)
      end

      test "a token or project Northflank refuses is said before anything is saved" do
        NorthflankApi.any_instance.stubs(:project).raises(NorthflankApi::Error, "Northflank answered 401: Unauthorized")

        refusal = Northflank.credential_refusal(Northflank::API_TOKEN => "wrong", Northflank::PROJECT => "firefight")

        assert_match "Northflank refused this token or project", refusal
        assert_match "401", refusal
        assert_equal "Paste an API token.", Northflank.credential_refusal(Northflank::PROJECT => "firefight")
      end

      test "the project's services and databases are listed with their state" do
        text = call(:list_resources)

        assert_match "web (web), combined service, completed", text
        assert_match "db (db), postgresql database, running", text
      end

      test "logs are searched on the named resource, newest first, with the filters it was given" do
        NorthflankApi.any_instance.expects(:logs).with do |project, kind, id, query|
          project == "firefight" && kind == Northflank::KIND_SERVICES && id == "web" &&
            query["textIncludes"] == "timeout" && query["direction"] == "backward" && query["type"] == "runtime"
        end.returns([ { "ts" => "2026-09-25T14:02:03Z", "containerId" => "web-1", "log" => "upstream timeout after 30s" } ])

        text = call(:search_logs, "resource" => "WEB", "text" => "timeout", "minutes" => 30)

        assert_match "2026-09-25T14:02:03Z web-1 upstream timeout after 30s", text
      end

      test "a kind of log the account does not have says so, and points at the runtime logs, rather than reading as a broken connection" do
        NorthflankApi.any_instance.stubs(:logs).raises(NorthflankApi::NotEnabled, "Northflank answered 401: Feature flag is not enabled for your account 2")

        text = call(:search_logs, "resource" => "web", "type" => "ingress")

        assert text.start_with?("Northflank has not switched on ingress logs for this account, so there are none to read. The connection works. " \
                                "Ask for type runtime instead, the service's own lines, which usually log each request's path and status.\n")
        assert_match %r{link with what you found: https://app\.northflank\.com/t/firefight-labs/project/firefight/services/web/observe/logs\?}, text
      end

      test "a metric Northflank sent nothing for is said in the text and never drawn, since no data is not zero" do
        NorthflankApi.any_instance.stubs(:metrics).returns(
          "requests" => { "metricInfo" => { "metricUnit" => "rps" }, "values" => [] },
          "cpu" => { "metricInfo" => { "metricUnit" => "pct" },
                     "values" => [ { "metadata" => { "containerId" => "web-1" }, "data" => [ { "ts" => "2026-09-25T14:00:00Z", "value" => 0.4 } ] } ] }
        )

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => %w[requests cpu] })

        assert_match "Requests of web: no data in that range. That does not show zero", result["content"].sole["text"]
        assert_equal [ "CPU of web" ], result.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::CHARTS).map { |chart| chart["title"] }
      end

      test "a log search that reaches its limit tells the model older lines were not returned" do
        lines = (1..3).map { |index| { "ts" => "2026-09-25T14:0#{index}:00Z", "containerId" => "web-1", "log" => "line #{index}" } }
        NorthflankApi.any_instance.stubs(:logs).returns(lines)

        assert_match "These are only the newest 3", call(:search_logs, "resource" => "web", "limit" => 3)
        assert_no_match "only the newest", call(:search_logs, "resource" => "web", "limit" => 10)
      end

      test "metrics come back as numbers for the model and as charts for the person, with a link to the service's metrics" do
        NorthflankApi.any_instance.stubs(:metrics).returns(
          "http5xxResponses" => {
            "metricInfo" => { "metricUnit" => "count" },
            "values" => [ { "metadata" => { "containerId" => "web-1" },
                            "data" => [ { "ts" => "2026-09-25T14:00:00Z", "value" => 0 }, { "ts" => "2026-09-25T14:05:00Z", "value" => 42 } ] } ]
          }
        )

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => [ "http5xxResponses" ] })

        text = result["content"].sole["text"]
        assert_match "5xx responses of web (count)", text
        assert_match "web-1: min 0.0, avg 21.0, max 42.0 at 2026-09-25T14:05:00Z", text
        chart = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).sole
        assert_equal [ [ "2026-09-25T14:00:00Z", 0.0 ], [ "2026-09-25T14:05:00Z", 42.0 ] ], chart["series"].sole["points"]
        assert_equal text.lines.last.split(": ", 2).last, chart["link"]
        assert_match %r{\Ahttps://app\.northflank\.com/t/firefight-labs/project/firefight/services/web/observe/metrics\?endDate=.+&range=custom&startDate=}, chart["link"]
      end

      test "logs link to the same search and time range on the service's Observe page, for the model to hand the person" do
        NorthflankApi.any_instance.stubs(:logs).returns([ { "ts" => "2026-09-25T14:02:03Z", "containerId" => "web-1", "log" => "probe" } ])

        text = call(:search_logs, "resource" => "web", "text" => "195.178.110.247", "start" => "2026-09-28T16:00:00Z", "end" => "2026-09-29T16:00:00Z")

        assert_includes text, "Open this in Northflank, and give the person this link with what you found: " \
                              "https://app.northflank.com/t/firefight-labs/project/firefight/services/web/observe/logs?" \
                              "endDate=2026-09-29T16%3A00%3A00.000Z&matchType=match&queryType=text&range=custom" \
                              "&searchQuery=195.178.110.247&startDate=2026-09-28T16%3A00%3A00.000Z"
      end

      test "a log link carries a regular expression, or text to leave out, when that was the search" do
        NorthflankApi.any_instance.stubs(:logs).returns([])

        assert_match "matchType=match&queryType=regex&range=custom&searchQuery=5%5Cd%5Cd", call(:search_logs, "resource" => "web", "regex" => "5\\d\\d")
        assert_match "matchType=noMatch&queryType=text&range=custom&searchQuery=health", call(:search_logs, "resource" => "web", "exclude" => "health")
      end

      test "a database's logs link to its page, since its Observe address has not been checked" do
        NorthflankApi.any_instance.stubs(:logs).returns([])

        assert_match %r{link with what you found: https://app\.northflank\.com/t/firefight-labs/project/firefight/addons/db\z}, call(:search_logs, "resource" => "db")
      end

      test "every tool's answer links to where it is on Northflank" do
        NorthflankApi.any_instance.stubs(logs: [], metrics: {}, builds: [], deployments: [], containers: [], build_logs: [],
                                         service: { "deployment" => {}, "healthChecks" => [] },
                                         jobs: [ { "id" => "nightly", "name" => "Nightly", "jobType" => "cron" } ], job_runs: [])
        arguments = { "resource" => "web", "job" => "nightly", "build" => "jovial-writer-6307" }
        links = Northflank.tool_definitions.to_h { |definition| [ definition.name.to_s, call(definition.name, arguments).lines.last ] }

        assert links.values.all? { |line| line.start_with?("Open this in Northflank") }, links.inspect
        assert_match %r{/project/firefight\z}, links["list_resources"]
        assert_match %r{/project/firefight/jobs\z}, links["list_jobs"]
        assert_match %r{/project/firefight/jobs/nightly/runs\z}, links["job_runs"]
        assert_match %r{/services/web/builds\z}, links["recent_builds"]
        assert_match %r{/services/web/builds/jovial-writer-6307\z}, links["build_logs"]
        assert_match %r{/services/web/deployments\z}, links["list_deployments"]
        assert_match %r{/services/web/observe\z}, links["list_containers"]
        assert_match %r{/services/web\z}, links["describe_resource"]
      end

      test "a metric with more containers than a chart keeps says how many were left out" do
        containers = (1..10).map { |index| { "metadata" => { "containerId" => "web-#{index}" }, "data" => [ { "ts" => "2026-09-25T14:00:00Z", "value" => index } ] } }
        NorthflankApi.any_instance.stubs(:metrics).returns("cpu" => { "metricInfo" => { "metricUnit" => "vCPU" }, "values" => containers })

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => [ "cpu" ] })

        assert_match "2 more series not shown, only the first 8 are kept", result["content"].sole["text"]
        assert_match "2 more series not shown", result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).sole["summary"]
      end

      test "a resource that is not in the project says what to do instead" do
        error = assert_raises(NativePack::Error) { call(:search_logs, "resource" => "checkout") }

        assert_match "list_resources shows what there is", error.message
      end

      test "a service is described with its rollout, what it runs, its health checks and ports" do
        NorthflankApi.any_instance.stubs(:service).with("firefight", "web").returns(
          "serviceType" => "combined", "billing" => { "deploymentPlan" => "nf-compute-100-2" },
          "status" => { "deployment" => { "status" => "COMPLETED", "reason" => "DEPLOYING", "lastTransitionTime" => "2026-09-24T13:06:48Z" } },
          "deployment" => { "instances" => 2, "storage" => { "ephemeralStorage" => { "storageSize" => 1024 } },
                            "internal" => { "repository" => "https://github.com/acme/app", "branch" => "main", "deployedSHA" => "c4e4267d" } },
          "healthChecks" => [ { "type" => "readinessProbe", "protocol" => "HTTP", "port" => 80, "path" => "/up", "periodSeconds" => 60,
                                "timeoutSeconds" => 10, "failureThreshold" => 3 } ],
          "ports" => [ { "name" => "p01", "internalPort" => 80, "protocol" => "HTTP", "public" => true } ]
        )

        text = call(:describe_resource, "resource" => "web")

        assert_match "COMPLETED means the latest deployment rolled out and is serving", text
        assert_match "Instances: 2, plan nf-compute-100-2", text
        assert_match "Runs https://github.com/acme/app, branch main, deployed commit c4e4267d", text
        assert_match "readinessProbe: HTTP port 80 /up, every 60s, timeout 10s, fails after 3 misses", text
        assert_match "Ports: p01 80 HTTP, public", text
      end

      test "a service without health checks says what that costs" do
        NorthflankApi.any_instance.stubs(:service).returns("serviceType" => "combined", "deployment" => {}, "healthChecks" => [])

        assert_match "Health checks: none, so Northflank cannot tell a hung process from a healthy one", call(:describe_resource, "resource" => "web")
      end

      test "a database is described with its status, storage and latest backups" do
        NorthflankApi.any_instance.stubs(:addon).with("firefight", "db").returns(
          "status" => "running",
          "spec" => { "type" => "postgresql", "config" => { "versionTag" => "16", "lifecycleStatus" => "active",
                                                             "deployment" => { "replicas" => 2, "storageSize" => 4096, "storageClass" => "nvme", "planId" => "nf-compute-20" },
                                                             "networking" => { "tlsEnabled" => true, "externalAccessEnabled" => false } } }
        )
        NorthflankApi.any_instance.stubs(:backups).returns([ { "createdAt" => "2026-09-28T02:00:00Z", "status" => "completed" } ])

        text = call(:describe_resource, "resource" => "db")

        assert_match "db, postgresql 16 database", text
        assert_match "Replicas: 2, storage 4096 MB nvme, plan nf-compute-20. Storage and replicas can only grow.", text
        assert_match "Latest backups: 2026-09-28T02:00:00Z completed", text
      end

      test "deployments say when, what and why, newest first" do
        NorthflankApi.any_instance.stubs(:deployments).with("firefight", "web", limit: 20).returns([
          { "createdAt" => "2026-09-24T13:05:25Z", "active" => true, "instances" => 1,
            "commit" => { "sha" => "c4e4267d46e638ac", "message" => "Argue with an answer\nmore", "author" => "ada" },
            "reason" => { "id" => "service-updated", "user" => { "name" => "Ada" } } }
        ])

        text = call(:list_deployments, "resource" => "web")

        assert_match "2026-09-24T13:05:25Z, active, 1 instances, c4e4267d46e6 \"Argue with an answer\" by ada, reason service-updated by Ada", text
      end

      test "containers are listed newest first in words, with how many run and failed" do
        NorthflankApi.any_instance.stubs(:containers).returns([
          { "name" => "web-old", "createdAt" => 1_790_000_000, "updatedAt" => 1_790_000_100, "status" => "TASK_FAILED" },
          { "name" => "web-new", "createdAt" => 1_790_000_200, "updatedAt" => 1_790_000_220, "status" => "TASK_RUNNING" }
        ])

        text = call(:list_containers, "resource" => "web")

        assert_match "web: 1 running, 1 failed, 2 listed, newest first.\nweb-new, running", text
        assert_match "web-old, failed", text
      end

      test "a job's runs are found by its name, and an unknown job says what to do" do
        NorthflankApi.any_instance.stubs(:jobs).returns([ { "id" => "nightly", "name" => "Nightly export", "jobType" => "cron" } ])
        NorthflankApi.any_instance.stubs(:job_runs).with("firefight", "nightly", limit: 20).returns([
          { "startedAt" => "2026-09-28T02:00:00Z", "concludedAt" => "2026-09-28T02:30:00Z", "status" => "FAILED", "failed" => 3 }
        ])

        assert_match "2026-09-28T02:00:00Z, failed, finished 2026-09-28T02:30:00Z, 3 failed attempts", call(:job_runs, "job" => "nightly export")
        assert_raises(NativePack::Error) { call(:job_runs, "job" => "weekly") }
      end

      test "the project goes on the map with what its services build from and serve, and a list the token may not read is a gap" do
        NorthflankApi.any_instance.stubs(:services).returns([ { "id" => "web" }, { "id" => "builder" } ])
        NorthflankApi.any_instance.stubs(:service).with("firefight", "web").returns(
          "id" => "web", "name" => "web", "serviceType" => "deployment", "appId" => "/firefight-labs/firefight/web",
          "status" => { "deployment" => { "status" => "COMPLETED" } },
          "deployment" => { "instances" => 2, "internal" => { "nfObjectId" => "builder", "deployedSHA" => "c4e4267d", "branch" => "main" } },
          "ports" => [ { "public" => true, "domains" => [ "app.acme.dev" ] }, { "public" => false, "domains" => [ "internal.acme.dev" ] } ]
        )
        NorthflankApi.any_instance.stubs(:service).with("firefight", "builder").returns(
          "id" => "builder", "name" => "builder", "serviceType" => "build", "appId" => "/firefight-labs/firefight/builder",
          "status" => { "build" => { "status" => "SUCCESS" } }, "vcsData" => { "projectUrl" => "https://github.com/acme/app" }
        )
        NorthflankApi.any_instance.stubs(:jobs).raises(NorthflankApi::Error, "Northflank answered 401: needs Jobs Read")

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.to_h { |resource| [ resource.external_id, resource ] }
        assert_equal ResourceMap::KIND_SERVICE, found["web"].kind
        assert_equal "firefight-labs/firefight", found["web"].account
        assert_equal "completed", found["web"].status
        assert_equal "https://app.northflank.com/t/firefight-labs/project/firefight/services/web", found["web"].url
        assert_equal ResourceMap::KIND_BUILD_SERVICE, found["builder"].kind
        assert_equal ResourceMap::KIND_REPOSITORY, found["acme/app"].kind
        assert_equal ResourceMap::KIND_DATABASE, found["db"].kind
        assert_not found.key?("internal.acme.dev"), "a private port's domain is not served to anyone"
        assert_equal [ [ "web", ResourceMap::RELATION_RUNS_BUILDS_OF, "builder" ], [ "app.acme.dev", ResourceMap::RELATION_SERVED_BY, "web" ],
                       [ "builder", ResourceMap::RELATION_BUILT_FROM, "acme/app" ] ],
                     snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
        assert_equal [ "Jobs could not be read: Northflank answered 401: needs Jobs Read" ], snapshot.gaps
      end

      test "a sweep that cannot reach Northflank leaves the map as it was and says why" do
        ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
          ResourceMap::Found.new(provider: "northflank", account: "firefight-labs/firefight", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
        ]))
        NorthflankApi.any_instance.stubs(:services).raises(NorthflankApi::Error, "Northflank answered 503")

        assert_not MapSweep.run!(@row)

        assert_equal "Northflank answered 503", @row.reload.map_error
        assert_nil ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web").removed_at
      end

      test "only services have builds" do
        error = assert_raises(NativePack::Error) { call(:recent_builds, "resource" => "db") }

        assert_match "only services have builds", error.message
      end

      private

      test "a week of metrics per service and database, grouped to Northflank's step, containers added up and counts made per minute" do
        web = ResourceMap::Resource.new(provider: "northflank", account: "firefight-labs/firefight", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
        db = ResourceMap::Resource.new(provider: "northflank", account: "firefight-labs/firefight", kind: ResourceMap::KIND_DATABASE, external_id: "db", name: "db")
        repository = ResourceMap::Resource.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/app", name: "acme/app")
        # Two containers reading a few seconds apart within each 5 minute step.
        two = ->(first, second) {
          [ { "data" => [ { "ts" => "2026-09-29T10:00:00Z", "value" => first }, { "ts" => "2026-09-29T10:05:00Z", "value" => first } ] },
            { "data" => [ { "ts" => "2026-09-29T10:00:04Z", "value" => second }, { "ts" => "2026-09-29T10:05:04Z", "value" => second } ] } ]
        }
        NorthflankApi.any_instance.expects(:metrics).with("firefight", "services", "web", has_entry("metricTypes", %w[requests http4xxResponses http5xxResponses cpu memory]))
                     .returns("requests" => { "metricInfo" => { "metricUnit" => "rps" }, "values" => two.(3, 4) },
                              "http5xxResponses" => { "metricInfo" => { "metricUnit" => "count" }, "values" => two.(10, 20) })
        NorthflankApi.any_instance.expects(:metrics).with("firefight", "addons", "db", has_entry("metricTypes", %w[cpu memory diskUsage]))
                     .returns("diskUsage" => { "metricInfo" => { "metricUnit" => "mb" }, "values" => two.(400, 600) })

        found = @pack.baselines_of(@row, [ web, db, repository ], 7.days.ago..Time.current)

        assert_equal [ [ "Requests", "requests/s", [ 7.0, 7.0 ] ], [ "5xx responses", "per minute", [ 6.0, 6.0 ] ], [ "Disk usage", "MB", [ 600.0, 600.0 ] ] ],
                     found.map { |each| [ each.label, each.unit, each.points.map(&:last) ] }
        assert_equal web.key, found.first.key
      end

      test "a resource Northflank cannot read is skipped, and being asked to slow down stops the read" do
        web = ResourceMap::Resource.new(provider: "northflank", account: "a", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
        db = ResourceMap::Resource.new(provider: "northflank", account: "a", kind: ResourceMap::KIND_DATABASE, external_id: "db", name: "db")
        points = [ { "ts" => "2026-09-29T10:00:00Z", "value" => 0.2 }, { "ts" => "2026-09-29T10:05:00Z", "value" => 0.3 } ]
        NorthflankApi.any_instance.stubs(:metrics).with("firefight", "services", "web", anything).raises(NorthflankApi::Error, "Northflank answered 404")
        NorthflankApi.any_instance.stubs(:metrics).with("firefight", "addons", "db", anything)
                     .returns("cpu" => { "metricInfo" => { "metricUnit" => "vCPU" }, "values" => [ { "data" => points } ] })

        assert_equal [ "CPU" ], @pack.baselines_of(@row, [ web, db ], 7.days.ago..Time.current).map(&:label)

        NorthflankApi.any_instance.stubs(:metrics).with("firefight", "services", "web", anything).raises(NorthflankApi::RateLimited, "Northflank answered 429")
        assert_raises(NorthflankApi::RateLimited) { @pack.baselines_of(@row, [ web, db ], 7.days.ago..Time.current) }
      end

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
