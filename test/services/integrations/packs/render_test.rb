require "test_helper"

module Integrations
  module Packs
    class RenderTest < ActiveSupport::TestCase
      WEB_PAGE = "https://dashboard.render.com/web/srv-web".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
        @row = @integration.integration_environments.create!
        Render.store_credentials!(@row, Render::API_KEY => " rnd_key ")
        @row.store_fields!(Render::WORKSPACE => "tea-1")
        @pack = Render.new(@integration)
        RenderApi.any_instance.stubs(:services).with("tea-1").returns(Integrations::Pages::Read.new(items: [
          { "id" => "srv-web", "name" => "web", "type" => "web_service", "suspended" => "not_suspended", "dashboardUrl" => WEB_PAGE,
            "repo" => "https://github.com/acme/app", "branch" => "main",
            "serviceDetails" => { "plan" => "standard", "region" => "oregon", "numInstances" => 2, "url" => "https://web.onrender.com" } },
          { "id" => "crn-1", "name" => "nightly", "type" => "cron_job", "suspended" => "suspended", "suspenders" => [ "stuck_crashlooping" ],
            "dashboardUrl" => "https://dashboard.render.com/cron/crn-1", "serviceDetails" => {} }
        ], complete: true))
        RenderApi.any_instance.stubs(:postgres_databases).with("tea-1").returns(Integrations::Pages::Read.new(items: [
          { "id" => "dpg-1", "name" => "db", "status" => "available", "version" => "16", "plan" => "pro_4gb", "region" => "oregon",
            "dashboardUrl" => "https://dashboard.render.com/d/dpg-1" }
        ], complete: true))
        RenderApi.any_instance.stubs(:key_values).with("tea-1").returns(Integrations::Pages::Read.new(items: [
          { "id" => "red-1", "name" => "cache", "status" => "available", "plan" => "starter", "dashboardUrl" => "https://dashboard.render.com/r/red-1" }
        ], complete: true))
      end

      test "the key and workspace are stored trimmed, and only the restart, rollback and scale change anything" do
        assert_equal "rnd_key", ConnectionSettings.of(@row.reload).credential(Render::API_KEY)
        assert_nil @row.credentials_hash[Render::WORKSPACE], "the workspace is a connect field, not a credential"
        assert_equal %w[restart_service rollback_deploy scale_service], Render.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a wrong key or workspace is said on the form before anything is saved" do
        RenderApi.any_instance.stubs(:owner).raises(RenderApi::Error, "Render answered 401: Authorization information is missing or invalid.")

        assert_equal "Paste an API key.", Render.credential_refusal({}, fields: { Render::WORKSPACE => "tea-1" })
        assert_match "Render refused this key or workspace: Render answered 401", Render.credential_refusal({ Render::API_KEY => "x" }, fields: { Render::WORKSPACE => "tea-1" })
        assert_match "can hold only tea- followed by lowercase letters and numbers", IntegrationProvider.find(Render::PROVIDER_KEY).connect_fields.sole.refusal("my-team")
      end

      test "the resources list says what each is and whether it runs, and a suspended one says why" do
        text = call(:list_resources)

        assert_match "web (srv-web), web service, running", text
        assert_match "nightly (crn-1), cron job, suspended by stuck_crashlooping", text
        assert_match "db (dpg-1), Postgres database, available", text
        assert_match "cache (red-1), Key Value instance, available", text
      end

      test "logs are asked newest first in the workspace, a regular expression goes between slashes, and the link is the service's page" do
        RenderApi.any_instance.expects(:logs).with do |query|
          query["ownerId"] == "tea-1" && query["resource"] == "srv-web" && query["direction"] == "backward" && query["type"] == "request" &&
            query["text"] == [ "timeout", "/5\\d\\d/" ] && query["limit"] == 50
        end.returns("hasMore" => true, "logs" => [
          { "message" => "GET /checkout 502", "timestamp" => "2026-10-01T10:00:00Z", "labels" => [ { "name" => "instance", "value" => "srv-web-abcde" } ] }
        ])

        text = call(:search_logs, "resource" => "WEB", "text" => "timeout", "regex" => "5\\d\\d", "type" => "request", "limit" => 50)

        assert_match "2026-10-01T10:00:00Z srv-web-abcde GET /checkout 502", text
        assert_match "These are only the newest 1", text
        assert text.end_with?(WEB_PAGE)
      end

      test "5xx is every 5xx status code added up, a metric the resource does not keep is named, and a static site has none" do
        RenderApi.any_instance.expects(:metrics).with("http-requests", has_entries("resource" => "srv-web", "aggregateBy" => "statusCode")).returns([
          { "labels" => [ { "field" => "statusCode", "value" => "502" } ], "unit" => "count",
            "values" => [ { "timestamp" => "2026-10-01T10:00:00Z", "value" => 3 } ] },
          { "labels" => [ { "field" => "statusCode", "value" => "503" } ], "unit" => "count",
            "values" => [ { "timestamp" => "2026-10-01T10:00:00Z", "value" => 2 } ] },
          { "labels" => [ { "field" => "statusCode", "value" => "200" } ], "unit" => "count",
            "values" => [ { "timestamp" => "2026-10-01T10:00:00Z", "value" => 90 } ] }
        ])

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => %w[http_5xx active_connections] })

        chart = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).sole
        assert_equal "5xx responses of web", chart["title"]
        assert_equal [ [ "2026-10-01T10:00:00Z", 5.0 ] ], chart["series"].sole["points"]
        assert_match "Render does not keep active_connections for a web service.", result["content"].sole["text"]
      end

      test "deploys name the commit, what triggered them and their page, and events say why an instance failed" do
        RenderApi.any_instance.stubs(:deploys).with("srv-web", limit: 20).returns([
          { "id" => "dep-2", "status" => "live", "trigger" => "new_commit", "createdAt" => "2026-10-01T09:00:00Z", "finishedAt" => "2026-10-01T09:04:00Z",
            "commit" => { "id" => "c4e4267d46e638ac", "message" => "Speed up checkout\nmore" } }
        ])
        RenderApi.any_instance.stubs(:events).returns([
          { "timestamp" => "2026-10-01T10:00:00Z", "type" => "server_failed",
            "details" => { "instanceID" => "srv-web-abcde", "reason" => { "evicted" => false, "oomKilled" => { "memoryLimit" => "2Gi" } } } },
          { "timestamp" => "2026-10-01T09:04:00Z", "type" => "deploy_ended",
            "details" => { "deployStatus" => "failed", "reason" => { "failure" => { "evicted" => false, "timedOutSeconds" => 900, "timedOutReason" => "no open port" } } } }
        ])

        deploys = call(:list_deployments, "resource" => "web")
        events = call(:list_events, "resource" => "web")

        assert_match "deploy dep-2, live, c4e4267d46e6 \"Speed up checkout\", triggered by new commit, finished 2026-10-01T09:04:00Z, page #{WEB_PAGE}/deploys/dep-2", deploys
        assert_match "server failed: ran out of memory, limit 2Gi", events
        assert_match "deploy ended: failed, timed out after 900 seconds: no open port", events
      end

      test "a service's status says how it scales, what it runs and what happened to it lately" do
        RenderApi.any_instance.stubs(:service).with("srv-web").returns(
          "type" => "web_service", "repo" => "https://github.com/acme/app", "branch" => "main",
          "serviceDetails" => { "plan" => "standard", "region" => "oregon", "runtime" => "node", "healthCheckPath" => "",
                                "autoscaling" => { "enabled" => true, "min" => 1, "max" => 4, "criteria" => { "cpu" => { "enabled" => true, "percentage" => 70 } } },
                                "envSpecificDetails" => { "startCommand" => "API_TOKEN=ghp_#{'a' * 36} npm start" } }
        )
        RenderApi.any_instance.stubs(:deploys).returns([])
        RenderApi.any_instance.stubs(:events).returns([])

        text = call(:describe_resource, "resource" => "web")

        assert_match "Autoscaling between 1 and 4 instances on cpu 70%", text
        assert_match "Runs https://github.com/acme/app, branch main, start command API_TOKEN=ghp_#{'a' * 36} npm start", text
        assert_match "Health check path: none, so Render only checks that a port is open", text
        assert_match "Events in the last day: none", text
      end

      test "a restart, rollback and scale reach the right endpoint, and what Render would ignore or cannot do is refused in words" do
        RenderApi.any_instance.expects(:restart_postgres).with("dpg-1").returns({})
        assert_match "Render is restarting db", call(:restart_service, "resource" => "db")
        assert_match "cannot restart a Key Value instance", assert_raises(NativePack::Error) { call(:restart_service, "resource" => "cache") }.message

        RenderApi.any_instance.expects(:rollback).with("srv-web", "dep-1").returns("id" => "dep-3")
        assert_match "Render is rolling web back to deploy dep-1, as deploy dep-3. Autodeploy is still on", call(:rollback_deploy, "resource" => "web", "deploy" => "dep-1")

        RenderApi.any_instance.stubs(:service).returns("serviceDetails" => { "autoscaling" => { "enabled" => true } })
        RenderApi.any_instance.expects(:scale).never
        assert_match "Autoscaling is on for web", assert_raises(NativePack::Error) { call(:scale_service, "resource" => "web", "instances" => 3) }.message
        assert_match "Render scales web services", assert_raises(NativePack::Error) { call(:scale_service, "resource" => "nightly", "instances" => 3) }.message
      end

      test "a scale with autoscaling off goes through and says from how many" do
        RenderApi.any_instance.stubs(:service).returns("serviceDetails" => { "numInstances" => 2, "autoscaling" => { "enabled" => false } })
        RenderApi.any_instance.expects(:scale).with("srv-web", 4).returns({})

        assert_match "Render is scaling web to 4 instances from 2.", call(:scale_service, "resource" => "web", "instances" => "4")
      end

      test "the workspace goes on the map with what each service builds from and serves, and a domain list it cannot read is a gap" do
        RenderApi.any_instance.stubs(:deploys).returns([ { "id" => "dep-2", "status" => "live", "commit" => { "id" => "c4e4267d" } } ])
        RenderApi.any_instance.stubs(:custom_domains).with("srv-web").raises(RenderApi::Error, "Render answered 403: no")

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.index_by(&:external_id)
        assert_equal [ ResourceMap::KIND_SERVICE, "live", WEB_PAGE, "c4e4267d" ],
                     [ found["srv-web"].kind, found["srv-web"].status, found["srv-web"].url, found["srv-web"].details[ResourceMap::DEPLOYED_COMMIT] ]
        assert_equal [ ResourceMap::KIND_JOB, "suspended" ], [ found["crn-1"].kind, found["crn-1"].status ]
        assert_equal ResourceMap::KIND_DATABASE, found["dpg-1"].kind
        assert_equal "Key Value instance", found["red-1"].details["type"]
        assert_equal [ [ "srv-web", ResourceMap::RELATION_BUILT_FROM, "acme/app" ], [ "web.onrender.com", ResourceMap::RELATION_SERVED_BY, "srv-web" ] ],
                     snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
        assert_equal [ [ "The custom domains of web could not be read: Render answered 403: no.", [ ResourceMap::KIND_DOMAIN ] ] ], snapshot.gaps.map { |gap| [ gap.text, gap.kinds ] }
      end

      test "a name two resources share is refused, with the ids to name one by" do
        RenderApi.any_instance.stubs(:key_values).returns(Integrations::Pages::Read.new(items: [ { "id" => "red-2", "name" => "db", "status" => "available" } ], complete: true))

        assert_match "More than one Render resource is called db: dpg-1, red-2. Name it by its id.", assert_raises(NativePack::Error) { call(:describe_resource, "resource" => "db") }.message
      end

      test "a list read only up to its bound is a gap, and what it holds is not taken as gone" do
        RenderApi.any_instance.stubs(:services).returns(Integrations::Pages::Read.new(items: [], complete: true))
        RenderApi.any_instance.stubs(:postgres_databases).returns(Integrations::Pages::Read.new(items: [ { "id" => "dpg-1", "name" => "db" } ], complete: false))

        snapshot = @pack.map_of(@row)

        assert_equal [ "Only the first 1 Postgres databases were read." ], snapshot.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DATABASE ], snapshot.unread_kinds
      end

      test "a service list cut short holds back the domains and repositories services put on the map too" do
        RenderApi.any_instance.stubs(:services).returns(Integrations::Pages::Read.new(items: [], complete: false))

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ], snapshot.unread_kinds
      end

      test "a week of cpu and memory per resource, instances added up, and being asked to slow down stops the read" do
        web = ResourceMap::Resource.new(provider: "render", account: "tea-1", kind: ResourceMap::KIND_SERVICE, external_id: "srv-web", name: "web",
                                        details: { "type" => "web service" })
        cache = ResourceMap::Resource.new(provider: "render", account: "tea-1", kind: ResourceMap::KIND_DATABASE, external_id: "red-1", name: "cache",
                                          details: { "type" => "Key Value instance" })
        two = [ { "unit" => "CPU", "values" => [ { "timestamp" => "2026-10-01T10:00:00Z", "value" => 0.2 } ] },
                { "unit" => "CPU", "values" => [ { "timestamp" => "2026-10-01T10:00:00Z", "value" => 0.3 } ] } ]
        RenderApi.any_instance.stubs(:metrics).returns([])
        RenderApi.any_instance.stubs(:metrics).with("cpu", has_entries("resource" => "srv-web", "resolutionSeconds" => 3600)).returns(two)

        found = @pack.baselines_of(@row, [ web, cache ], 7.days.ago..Time.current)

        assert_equal [ [ "cpu", "CPU", [ 0.5 ] ] ], found.map { |each| [ each.metric, each.unit, each.points.map(&:last) ] }
        RenderApi.any_instance.stubs(:metrics).raises(RenderApi::Error.new("Render answered 429: rate limit exceeded").extend(Integrations::RateLimited))
        assert_raises(Integrations::RateLimited) { @pack.baselines_of(@row, [ web ], 7.days.ago..Time.current) }
      end

      test "the health check reads the workspace" do
        RenderApi.any_instance.stubs(:owner).with("tea-1").raises(RenderApi::Error, "Render answered 404: not found")

        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
