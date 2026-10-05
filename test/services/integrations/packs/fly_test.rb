require "test_helper"

module Integrations
  module Packs
    class FlyTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly.io")
        @row = @integration.integration_environments.create!
        Fly.store_credentials!(@row, Fly::API_TOKEN => " FlyV1 fm2_x ")
        @row.store_fields!(Fly::ORGANIZATION => "acme")
        @pack = Fly.new(@integration)
        FlyApi.any_instance.stubs(:app_list).with("acme")
              .returns(Integrations::Pages::Read.new(items: [ { "name" => "web", "status" => "deployed", "machine_count" => 2 } ], complete: true))
        FlyApi.any_instance.stubs(:postgres_clusters).with("acme").returns([
          { "id" => "pg1", "name" => "main-db", "status" => "ready", "plan" => "basic", "region" => "iad", "attached_apps" => [ { "name" => "web" } ] }
        ])
      end

      test "the token and organization are stored trimmed, and only the restart and rollback change anything" do
        assert_equal "FlyV1 fm2_x", ConnectionSettings.of(@row.reload).credential(Fly::API_TOKEN)
        assert_equal %w[restart_app rollback_release], Fly.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a wrong token or organization is said on the form, and the health check lists the organization's apps" do
        FlyApi.any_instance.stubs(:apps).raises(FlyApi::Error, "Fly answered 401: unauthorized")

        assert_equal "Enter the organization's slug.", Fly.credential_refusal({ Fly::API_TOKEN => "x" })
        assert_match "Fly.io refused this token or organization: Fly answered 401", Fly.credential_refusal({ Fly::API_TOKEN => "x" }, fields: { Fly::ORGANIZATION => "acme" })
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      test "the resources list names apps and clusters with their status" do
        text = call(:list_resources)

        assert_match "web, app, deployed, 2 machines", text
        assert_match "main-db (pg1), Managed Postgres cluster, ready", text
      end

      test "logs are read from the range's start, kept by text and regex on Firefight's side, newest first, linked to monitoring" do
        started = Time.zone.parse("2026-10-01T10:00:00Z")
        FlyApi.any_instance.expects(:logs).with("web", next_token: (started.to_r * 1_000_000_000).to_i.to_s).returns(
          "data" => [ entry("2026-10-01T10:01:00Z", "GET /checkout 502"), entry("2026-10-01T10:02:00Z", "GET /health 200"),
                      entry("2026-10-01T10:03:00Z", "POST /checkout 502") ],
          "meta" => { "next_token" => "2" }
        )
        FlyApi.any_instance.expects(:logs).with("web", next_token: "2").returns("data" => [ entry("2026-10-01T12:00:00Z", "later") ], "meta" => {})

        text = call(:search_logs, "resource" => "web", "text" => "checkout", "regex" => "^POST", "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T11:00:00Z")

        assert_match "1 log lines for web", text
        assert_match "2026-10-01T10:03:00Z m1 iad info POST /checkout 502", text
        assert_no_match "later", text
        assert text.end_with?("https://fly.io/apps/web/monitoring")
      end

      test "a regular expression that does not read is refused in words" do
        assert_match "does not read", assert_raises(NativePack::Error) { call(:search_logs, "resource" => "web", "regex" => "(") }.message
      end

      test "5xx is asked of Fly's edge per minute, and memory per machine in MB" do
        FlyApi.any_instance.expects(:query_range).with("acme", has_entry(:query, includes("status=~\"5..\""))).returns([
          { "metric" => {}, "values" => [ [ 1_790_000_000, "3" ], [ 1_790_000_060, "NaN" ] ] }
        ])
        FlyApi.any_instance.expects(:query_range).with("acme", has_entry(:query, includes("fly_instance_memory_mem_available{app=\"web\"}"))).returns([
          { "metric" => { "instance" => "m1" }, "values" => [ [ 1_790_000_000, "256.5" ] ] }
        ])

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => %w[http_5xx memory] })

        charts = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS)
        assert_equal [ "5xx responses of web", "per minute", "web", 1 ], [ charts.first["title"], charts.first["unit"], charts.first["series"].sole["label"], charts.first["series"].sole["points"].size ]
        assert_equal [ "m1", 256.5 ], [ charts.last["series"].sole["label"], charts.last["series"].sole["points"].sole.last ]
        assert result["content"].sole["text"].end_with?("https://fly.io/apps/web/metrics")
      end

      test "releases are newest first with what rollback takes" do
        FlyApi.any_instance.stubs(:releases).returns([
          { "version" => 41, "status" => "complete", "stable" => true, "description" => "Deploy image", "createdAt" => "2026-09-30T10:00:00Z",
            "user" => { "email" => "ada@acme.dev" }, "imageRef" => "registry.fly.io/web:deployment-41" },
          { "version" => 42, "status" => "failed", "stable" => false, "description" => "Deploy image", "createdAt" => "2026-10-01T10:00:00Z" }
        ])

        text = call(:list_deployments, "resource" => "web")

        assert_match "rollback_release takes a version.\n2026-10-01T10:00:00Z, v42, failed", text
        assert_match "v41, complete, stable, Deploy image, by ada@acme.dev, image registry.fly.io/web:deployment-41", text
      end

      test "a machine's status says why it exited, and how its checks stand" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started", events: [
          { "type" => "exit", "status" => "stopped", "timestamp" => 1_790_000_000_000,
            "request" => { "exit_event" => { "exit_code" => 137, "oom_killed" => true }, "restart_count" => 2 } }
        ]), machine("rc", "stopped", group: "fly_app_release_command") ])

        text = call(:describe_resource, "resource" => "web")

        assert_match "web, app, status deployed, 1 machines", text
        assert_match "Machine m1, started, region iad", text
        assert_match "Checks: servicecheck-00-http-8080 critical: connection refused", text
        assert_match "exit stopped (ran out of memory, exit code 137, restart 2)", text
        assert_no_match "Machine rc", text
      end

      test "a restart goes one machine at a time, waits for each to start, and stops at one that fails" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("m2", "started"), machine("m4", "started"), machine("m3", "stopped") ])
        FlyApi.any_instance.expects(:restart_machine).with("web", "m1").returns({})
        FlyApi.any_instance.expects(:wait_started).with("web", "m1", version: nil).returns(true)
        FlyApi.any_instance.expects(:restart_machine).with("web", "m2").raises(FlyApi::Error, "Fly answered 400: machine is busy")
        FlyApi.any_instance.expects(:restart_machine).with("web", "m4").never

        text = call(:restart_app, "resource" => "web")

        assert_match "m1 in iad: restarted, started again", text
        assert_match "m2 in iad: not changed, 400: machine is busy", text
        assert_match "Stopped there, so 1 more machines were left as they were.", text
        assert_match "1 stopped machines were left as they are.", text
      end

      test "a rollback moves each machine to the release's image, guarded by its version, and stops at one that changed" do
        FlyApi.any_instance.stubs(:releases).returns([ { "version" => 41, "id" => "r41", "imageRef" => "registry.fly.io/web:deployment-41" } ])
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("m2", "started") ])
        FlyApi.any_instance.expects(:update_machine).with("web", "m1", config: has_entry("image", "registry.fly.io/web:deployment-41"), current_version: "v-m1")
              .returns("version" => "v-m1-new")
        FlyApi.any_instance.expects(:wait_started).with("web", "m1", version: "v-m1-new").returns(true)
        FlyApi.any_instance.expects(:update_machine).with("web", "m2", anything).raises(FlyApi::Conflict, "Fly answered 409: version mismatch")

        text = call(:rollback_release, "resource" => "web", "release" => "v41")

        assert_match "m1 in iad: moved to the image, started again", text
        assert_match "m2 in iad: not changed, it changed since it was read", text
        assert_match "has no release v40", assert_raises(NativePack::Error) { call(:rollback_release, "resource" => "web", "release" => "40") }.message
      end

      test "a machine that does not start again on the release's image stops the rollback there" do
        FlyApi.any_instance.stubs(:releases).returns([ { "version" => 41, "id" => "r41", "imageRef" => "registry.fly.io/web:deployment-41" } ])
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("m2", "started") ])
        FlyApi.any_instance.expects(:update_machine).once.returns("version" => "v-m1-new")
        FlyApi.any_instance.stubs(:wait_started).returns(false)

        text = call(:rollback_release, "resource" => "web", "release" => "41")

        assert_match "m1 in iad: moved to the image, but not started again within #{FlyApi::WAIT_SECONDS} seconds", text
        assert_match "Stopped there, so 1 more machines were left as they were. Check m1 in iad in Fly.io before going on.", text
      end

      test "the organization goes on the map with each app's machines, the hostnames it serves and the clusters it uses" do
        FlyApi.any_instance.stubs(:machines).with("web").returns([ machine("m1", "started"), machine("m2", "started", region: "ams") ])
        FlyApi.any_instance.stubs(:certificates).with("web").returns([ { "hostname" => "app.acme.dev" } ])

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.index_by(&:external_id)
        assert_equal [ ResourceMap::KIND_SERVICE, "acme", "deployed", "https://fly.io/apps/web" ],
                     [ found["web"].kind, found["web"].account, found["web"].status, found["web"].url ]
        assert_equal({ "instances" => 2, "region" => "ams, iad", "image" => "registry.fly.io/web:deployment-41" }, found["web"].details)
        assert_equal [ ResourceMap::KIND_DATABASE, "https://fly.io/dashboard/acme/managed_postgres/pg1" ], [ found["pg1"].kind, found["pg1"].url ]
        assert_equal [ [ "app.acme.dev", ResourceMap::RELATION_SERVED_BY, "web" ], [ "web", ResourceMap::RELATION_USES, "pg1" ] ],
                     snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
        assert_empty snapshot.gaps
      end

      test "what could not be read for an app is a gap, not a failed sweep" do
        FlyApi.any_instance.stubs(:machines).raises(FlyApi::Error, "Fly answered 403: forbidden")
        FlyApi.any_instance.stubs(:certificates).returns([])
        FlyApi.any_instance.stubs(:postgres_clusters).raises(FlyApi::Error, "Fly answered 404: not found")

        snapshot = @pack.map_of(@row)

        assert_equal [ [ "The machines of web could not be read: Fly answered 403: forbidden.", [] ],
                       [ "Managed Postgres clusters could not be read: Fly answered 404: not found.", [ ResourceMap::KIND_DATABASE ] ] ],
                     snapshot.gaps.map { |gap| [ gap.text, gap.kinds ] }
        assert_equal [ ResourceMap::KIND_DATABASE ], snapshot.unread_kinds, "a cluster list Fly refused takes no cluster off the map"
      end

      test "an app list cut short at its bound is a gap, and its apps and domains are not taken as gone" do
        FlyApi.any_instance.stubs(:app_list).returns(Integrations::Pages::Read.new(items: [], complete: false))
        FlyApi.any_instance.stubs(:postgres_clusters).returns([])

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds
      end

      test "a week of cpu, memory and requests for the whole app, and being asked to slow down stops the read" do
        web = ResourceMap::Resource.new(provider: "fly", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
        db = ResourceMap::Resource.new(provider: "fly", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "pg1", name: "main-db")
        FlyApi.any_instance.stubs(:query_range).returns([])
        FlyApi.any_instance.stubs(:query_range).with("acme", has_entries(step: 3600, query: includes("fly_instance_cpu{app=\"web\""))).returns([
          { "metric" => {}, "values" => [ [ 1_790_000_000, "0.4" ] ] }
        ])

        found = @pack.baselines_of(@row, [ web, db ], 7.days.ago..Time.current)

        assert_equal [ [ "cpu", "CPUs", [ 0.4 ] ] ], found.map { |each| [ each.metric, each.unit, each.points.map(&:last) ] }
        FlyApi.any_instance.stubs(:query_range).raises(FlyApi::Error.new("Fly answered 429").extend(Integrations::RateLimited))
        assert_raises(Integrations::RateLimited) { @pack.baselines_of(@row, [ web ], 7.days.ago..Time.current) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end

      def entry(at, message)
        { "id" => at, "attributes" => { "timestamp" => at, "message" => message, "level" => "info", "instance" => "m1", "region" => "iad" } }
      end

      def machine(id, state, group: "app", region: "iad", events: [])
        { "id" => id, "state" => state, "region" => region, "version" => "v-#{id}",
          "image_ref" => { "registry" => "registry.fly.io", "repository" => "web", "tag" => "deployment-41" },
          "config" => { "image" => "registry.fly.io/web:deployment-42", "guest" => { "cpus" => 1, "cpu_kind" => "shared", "memory_mb" => 256 },
                        "metadata" => { "fly_platform_version" => "v2", "fly_process_group" => group },
                        "restart" => { "policy" => "on-failure", "max_retries" => 10 }, "services" => [ { "internal_port" => 8080 } ] },
          "checks" => [ { "name" => "servicecheck-00-http-8080", "status" => "critical", "output" => "connection refused" } ],
          "events" => events }
      end
    end
  end
end
