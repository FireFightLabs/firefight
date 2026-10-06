require "test_helper"

module Integrations
  module Packs
    class NorthflankTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
        @row = @integration.integration_environments.create!
        Northflank.store_credentials!(@row, Northflank::API_TOKEN => " nf-token ")
        @row.store_fields!(Northflank::PROJECT => "firefight")
        @pack = Northflank.new(@integration)
        NorthflankApi.any_instance.stubs(:services).returns(listed([
          { "id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/firefight-labs/firefight/web",
            "status" => { "deployment" => { "status" => "COMPLETED" } } }
        ]))
        NorthflankApi.any_instance.stubs(:addons).returns(listed([
          { "id" => "db", "name" => "db", "spec" => { "type" => "postgresql" }, "status" => "running", "appId" => "/firefight-labs/firefight/db" }
        ]))
        NorthflankApi.any_instance.stubs(:secret_groups).returns(listed([]))
      end

      test "the token and project are stored trimmed, and every tool only reads except the one that changes the project" do
        assert_equal "nf-token", @row.reload.credentials_hash[Northflank::API_TOKEN]
        assert_equal [ "api_request" ], Northflank.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a change goes to a path inside the project only, with its body, and links to what it changed" do
        NorthflankApi.any_instance.expects(:request).with("POST", "firefight", "services/web/scale", { "instances" => 3 })
                     .returns("data" => { "instances" => 3 })

        text = call(:api_request, "method" => "post", "path" => "/services/web/scale", "body" => { "instances" => 3 })

        assert text.start_with?("Northflank answered POST services/web/scale.\n{\"data\":{\"instances\":3}}")
      end

      test "every method reaches the API, and what holds secrets comes back as names only, with anything credential-like redacted" do
        NorthflankApi.any_instance.stubs(:request).with("GET", "firefight", "services/web/runtime-environment", nil)
                     .returns("data" => { "runtimeEnvironment" => { "DATABASE_URL" => "postgres://app:hunter2@db/prod", "PORT" => "3000" } })
        NorthflankApi.any_instance.stubs(:request).with("GET", "firefight", "secrets", nil)
                     .returns("data" => { "secrets" => [ { "id" => "app-env", "name" => "App env", "data" => { "KEY" => "value" } } ] })
        NorthflankApi.any_instance.stubs(:request).with("GET", "firefight", "services/web", nil)
                     .returns("data" => { "id" => "web", "note" => "token ghp_#{'a' * 36}", "runtimeEnvironment" => { "API_KEY" => "abc123" } })
        NorthflankApi.any_instance.stubs(:request).with("DELETE", "firefight", "jobs/nightly", nil).returns({})

        environment = call(:api_request, "method" => "GET", "path" => "services/web/runtime-environment")
        assert_match "\"DATABASE_URL\":\"[hidden]\"", environment
        assert_no_match "hunter2", environment
        assert_match "{\"id\":\"app-env\",\"name\":\"App env\",\"data\":{\"KEY\":\"[hidden]\"}}", call(:api_request, "method" => "GET", "path" => "secrets")
        service = call(:api_request, "method" => "GET", "path" => "services/web")
        assert_match "token [REDACTED:github_token]", service
        assert_match "\"runtimeEnvironment\":{\"API_KEY\":\"[hidden]\"}", service
        NorthflankApi.any_instance.stubs(:request).with("GET", "firefight", "addons/db/credentials-details", nil)
                     .returns("data" => { "envs" => { "PASSWORD" => "s3cret" }, "hosts" => [ "db.internal" ] })
        assert_no_match "s3cret", call(:api_request, "method" => "GET", "path" => "addons/db/credentials-details")
        assert call(:api_request, "method" => "DELETE", "path" => "jobs/nightly").start_with?("Northflank answered DELETE jobs/nightly.\n")
        assert_match %r{link with what you found: https://app\.northflank\.com/t/firefight-labs/project/firefight/services/web\z}, environment
      end

      test "a change outside the project, or not shaped as asked, is refused before anything is sent" do
        NorthflankApi.any_instance.expects(:request).never

        [ { "method" => "OPTIONS", "path" => "services/web" }, { "method" => "POST", "path" => "../other/services/web/restart" },
          { "method" => "POST", "path" => "services/web/restart?x=1" }, { "method" => "POST", "path" => "services/web/scale", "body" => "3" },
          { "method" => "POST", "path" => "services/%2e%2e/restart" }, { "method" => "POST", "path" => "services\\web" },
          { "method" => "POST", "path" => "services//restart" }, { "method" => "POST", "path" => "services/web/" },
          { "method" => "POST", "path" => "services/web/runtime-environment", "body" => { "DATABASE_URL" => "postgres://app:hunter2@db/prod" } } ].each do |arguments|
          assert_raises(Integrations::Error) { call(:api_request, arguments) }
        end
      end

      test "the link is found before the change, so a change that went through is never reported as failed for want of it" do
        NorthflankApi.any_instance.expects(:request).never
        @pack.stubs(:change_link).raises(NorthflankApi::Error, "Northflank answered 429: slow down")

        assert_raises(NorthflankApi::Error) { call(:api_request, "method" => "POST", "path" => "services/web/restart") }
      end

      test "a change the token's role may not make says what to give it in Northflank" do
        NorthflankApi.any_instance.stubs(:request).raises(NorthflankApi::Error, "Northflank answered 403: Missing permission: Update")

        error = assert_raises(Integrations::Error) { call(:api_request, "method" => "POST", "path" => "services/web/restart") }

        assert_match "The API token's role cannot make this change", error.message
      end

      # Seen in a real chat, Halon guessed POST pipelines three times, a call Northflank's API does not have.
      test "a path Northflank does not know, or a method it does not take there, sends Halon to the API reference" do
        [ "Northflank answered 405: Method Not Allowed", "Northflank answered 404: Not Found" ].each do |answer|
          NorthflankApi.any_instance.stubs(:request).raises(NorthflankApi::Error, answer)

          error = assert_raises(Integrations::Error) { call(:api_request, "method" => "POST", "path" => "pipelines", "body" => { "name" => "faylee" }) }

          assert_match answer, error.message
          assert_match "Northflank's API may not offer this call", error.message
          assert_match "never send the same call again", error.message
        end
      end

      test "a token or project Northflank refuses is said before anything is saved" do
        NorthflankApi.any_instance.stubs(:project).raises(NorthflankApi::Error, "Northflank answered 401: Unauthorized")

        refusal = Northflank.credential_refusal({ Northflank::API_TOKEN => "wrong" }, fields: { Northflank::PROJECT => "firefight" })

        assert_match "Northflank refused this token or project", refusal
        assert_match "401", refusal
        assert_equal "Paste an API token.", Northflank.credential_refusal({}, fields: { Northflank::PROJECT => "firefight" })
        assert_equal "Enter the project id.", Northflank.credential_refusal({ Northflank::API_TOKEN => "nf" })
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
                                         jobs: listed([ { "id" => "nightly", "name" => "Nightly", "jobType" => "cron" } ]), job_runs: [], request: {})
        arguments = { "resource" => "web", "job" => "nightly", "build" => "jovial-writer-6307", "method" => "POST", "path" => "services/web/restart" }
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
        assert_match %r{/services/web\z}, links["api_request"]
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
        assert_match "Ports:\n  p01 80 HTTP, public", text
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
        NorthflankApi.any_instance.stubs(:jobs).returns(listed([ { "id" => "nightly", "name" => "Nightly export", "jobType" => "cron" } ]))
        NorthflankApi.any_instance.stubs(:job_runs).with("firefight", "nightly", limit: 20).returns([
          { "startedAt" => "2026-09-28T02:00:00Z", "concludedAt" => "2026-09-28T02:30:00Z", "status" => "FAILED", "failed" => 3 }
        ])

        assert_match "2026-09-28T02:00:00Z, failed, finished 2026-09-28T02:30:00Z, 3 failed attempts", call(:job_runs, "job" => "nightly export")
        assert_raises(NativePack::Error) { call(:job_runs, "job" => "weekly") }
      end

      test "the project goes on the map with what its services build from and serve, and a list the token may not read is a gap" do
        NorthflankApi.any_instance.stubs(:services).returns(listed([ { "id" => "web" }, { "id" => "builder" } ]))
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
        assert_equal [ "Jobs could not be read: Northflank answered 401: needs Jobs Read." ], snapshot.gap_texts
        assert_equal [ ResourceMap::KIND_JOB ], snapshot.unread_kinds, "jobs it could not read are not taken as gone"
      end

      test "a service's own settings and those its secret groups give it are read in memory, and a linked database is a declared use" do
        own = "postgres://web:nf-own-pw@primary.db--abcd.addon.code.run:5432/app"
        NorthflankApi.any_instance.stubs(:services).returns(listed([ { "id" => "web" }, { "id" => "worker" } ]))
        NorthflankApi.any_instance.stubs(:service).with("firefight", "web").returns(
          "id" => "web", "name" => "web", "serviceType" => "deployment", "appId" => "/firefight-labs/firefight/web", "tags" => [ "api" ],
          "runtimeEnvironment" => { "DATABASE_URL" => own, "LOG_LEVEL" => "info" }
        )
        NorthflankApi.any_instance.stubs(:service).with("firefight", "worker").returns(
          "id" => "worker", "name" => "worker", "serviceType" => "deployment", "appId" => "/firefight-labs/firefight/worker"
        )
        NorthflankApi.any_instance.stubs(:jobs).returns(listed([]))
        NorthflankApi.any_instance.stubs(:secret_groups).with("firefight").returns(listed([
          { "id" => "db-secrets", "priority" => 10, "restrictions" => { "restricted" => true, "nfObjects" => [ { "id" => "web", "type" => "service" } ] } },
          { "id" => "tagged", "priority" => 20, "restrictions" => { "restricted" => true, "tags" => [ "api" ], "tagMatchCondition" => "or" } }
        ]))
        NorthflankApi.any_instance.stubs(:secret_group).with("firefight", "db-secrets").returns(
          "secrets" => { "variables" => { "DATABASE_URL" => "postgres://web:nf-group-pw@elsewhere.example.com/app", "CACHE_URL" => "redis://default:nf-cache-pw@cache.internal:6379" } },
          "addonSecrets" => [ { "id" => "db", "addonType" => "postgresql", "variables" => [ { "keyName" => "POSTGRES_URI", "aliases" => [ "DATABASE_URL" ] } ] } ]
        )
        NorthflankApi.any_instance.stubs(:secret_group).with("firefight", "tagged").returns("addonSecrets" => [ { "id" => "db", "variables" => { "DB_HOST" => "x" } } ])

        snapshot = @pack.map_of(@row)

        web = snapshot.uses.select { |use| use.from.last == "web" }.index_by(&:variable)
        assert_equal %w[CACHE_URL DATABASE_URL], web.keys.sort
        assert_equal ResourceMap::Fingerprint.of("primary.db--abcd.addon.code.run", 5432, @workspace), web["DATABASE_URL"].fingerprint, "the service's own value wins"
        assert_empty snapshot.uses.select { |use| use.from.last == "worker" }
        uses = snapshot.links.select { |link| link.relation == ResourceMap::RELATION_USES }
        assert_equal [ [ "web", "db", %w[DATABASE_URL DB_HOST] ] ], uses.map { |link| [ link.from.last, link.to.last, link.variables ] }
        ResourceMap.record!(@row, snapshot)
        assert_no_setting_values(snapshot, own, "nf-own-pw", "nf-group-pw", "nf-cache-pw", "cache.internal", "primary.db--abcd.addon.code.run")
      end

      test "secret groups the token may not read are a settings gap naming the permission, and nothing is held back" do
        NorthflankApi.any_instance.stubs(:service).returns("id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/firefight-labs/firefight/web")
        NorthflankApi.any_instance.stubs(:jobs).returns(listed([]))
        NorthflankApi.any_instance.stubs(:secret_groups).raises(NorthflankApi::Error, "Northflank answered 403: Forbidden")

        snapshot = @pack.map_of(@row)

        assert_equal [ "Secret groups could not be read: Northflank answered 403: Forbidden. #{Northflank::SECRETS_PERMISSION}" ], snapshot.gap_texts
        assert snapshot.complete?
        assert_not snapshot.settings_complete?

        NorthflankApi.any_instance.stubs(:secret_groups).raises(NorthflankApi::RateLimited, "Northflank answered 429")
        assert_equal [ Northflank::SLOWED ], Northflank.new(@integration).map_of(@row).gap_texts
      end

      test "a list cut short at the page bound is a gap naming what it holds, so nothing past it is taken as gone" do
        NorthflankApi.any_instance.stubs(:services).returns(listed([], complete: false))
        NorthflankApi.any_instance.stubs(:addons).returns(listed([], complete: false))
        NorthflankApi.any_instance.stubs(:jobs).returns(listed([], complete: false))

        snapshot = @pack.map_of(@row)

        assert_equal [ "The project has more than 1000 services, so only the first 1000 are on the map.",
                       "The project has more than 1000 databases, so only the first 1000 are on the map.",
                       "The project has more than 1000 jobs, so only the first 1000 are on the map." ], snapshot.gap_texts
        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_BUILD_SERVICE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY,
                       ResourceMap::KIND_DATABASE, ResourceMap::KIND_JOB ], snapshot.unread_kinds
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

      def listed(items, complete: true) = Pages::Read.new(items: items, complete: complete)

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
