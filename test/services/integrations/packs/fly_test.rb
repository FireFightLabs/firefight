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
        FlyApi.any_instance.stubs(:secret_names).returns([])
      end

      test "the token and organization are stored trimmed, and only the machine changes change anything" do
        assert_equal "FlyV1 fm2_x", ConnectionSettings.of(@row.reload).credential(Fly::API_TOKEN)
        assert_equal %w[restart_app rollback_release start_app stop_app suspend_app cordon_machine uncordon_machine scale_app resize_app],
                     Fly.tool_definitions.reject(&:read_only).map(&:name)
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

      test "the resources list says when clusters could not be read or the apps were cut short, and never calls a resource missing for it" do
        FlyApi.any_instance.stubs(:app_list).with("acme")
              .returns(Integrations::Pages::Read.new(items: [ { "name" => "web", "status" => "deployed", "machine_count" => 2 } ], complete: false))
        FlyApi.any_instance.stubs(:postgres_clusters).raises(FlyApi::Error, "Fly answered 403: forbidden")

        text = call(:list_resources)

        assert_match "Only the first 1 apps were read.", text
        assert_match "Managed Postgres clusters could not be read: Fly answered 403: forbidden.", text
        assert_match "describe_resource", text

        FlyApi.any_instance.stubs(:app).with("far").returns("name" => "far", "status" => "suspended")
        FlyApi.any_instance.stubs(:machines).with("far").returns([])
        assert_match "far, app, status suspended", call(:describe_resource, "resource" => "far")

        FlyApi.any_instance.stubs(:app).with("main-db").raises(FlyApi::Error, "Fly answered 404: not found")
        error = assert_raises(Integrations::Error) { call(:describe_resource, "resource" => "main-db") }
        assert_equal "Nothing called main-db among the first 1 apps read, and Managed Postgres clusters could not be read: Fly answered 403: forbidden.",
                     error.message
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

      test "releases are kept as deploys by id and version, with how each rolled out" do
        FlyApi.any_instance.stubs(:releases).returns([
          { "id" => "r41", "version" => 41, "status" => "complete", "stable" => true, "createdAt" => "2026-09-30T10:00:00Z", "updatedAt" => "2026-09-30T10:04:00Z",
            "imageRef" => "registry.fly.io/web:deployment-41" },
          { "id" => "r42", "version" => 42, "status" => "running", "stable" => false, "createdAt" => "2026-10-01T10:00:00Z", "updatedAt" => "2026-10-01T10:01:00Z" }
        ])

        result = @pack.call("list_deployments", environment_row: @row, arguments: { "resource" => "web" })
        deploys = Capabilities::Deploys.deploys_of(result)

        assert_equal [ [ "r42", "42", Capabilities::History::RUNNING, nil ], [ "r41", "41", Capabilities::History::SUCCEEDED, Time.utc(2026, 9, 30, 10, 4) ] ],
                     deploys.map { |deploy| [ deploy.id, deploy.version, deploy.status, deploy.finished_at ] }
        assert_equal [ nil, nil ], deploys.map(&:commit)
        assert_equal [ nil, nil ], deploys.map(&:live)
        assert_equal Time.utc(2026, 10, 1, 10), deploys.first.started_at
        assert_equal "r41", Capabilities::Deploys.live(deploys).id
        assert_match "v41, complete, stable", result["content"].sole["text"]
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

      test "a start brings up each stopped or suspended machine and waits for it, and one already running is said in words" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "stopped"), machine("m2", "suspended"), machine("m3", "started") ])
        FlyApi.any_instance.expects(:start_machine).with("web", "m1").returns({})
        FlyApi.any_instance.expects(:start_machine).with("web", "m2").returns({})
        FlyApi.any_instance.expects(:start_machine).with("web", "m3").never
        FlyApi.any_instance.stubs(:wait_started).returns(true)

        text = call(:start_app, "resource" => "web")

        assert_match "m1 in iad: started, started again", text
        assert_match "m2 in iad: started, started again", text
        assert_equal "Machine m3 of web is started, so there is nothing to start.",
                     assert_raises(NativePack::Error) { call(:start_app, "resource" => "web", "machine" => "m3") }.message
      end

      test "a restart with nothing running points at the start" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "stopped") ])

        assert_match "start_app starts its stopped machines", assert_raises(NativePack::Error) { call(:restart_app, "resource" => "web") }.message
      end

      test "a stop and a suspend wait for each machine to reach that state, and stop at one that does not" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("m2", "started"), machine("m3", "stopped") ])
        FlyApi.any_instance.expects(:stop_machine).with("web", "m1").returns({})
        FlyApi.any_instance.expects(:wait_for).with("web", "m1", "stopped", version: nil).returns(false)
        FlyApi.any_instance.expects(:stop_machine).with("web", "m2").never

        text = call(:stop_app, "resource" => "web")
        assert_match "m1 in iad: asked, but not stopped within #{FlyApi::WAIT_SECONDS} seconds", text
        assert_match "Stopped there, so 1 more machines were left as they were.", text

        FlyApi.any_instance.expects(:suspend_machine).with("web", "m2").returns({})
        FlyApi.any_instance.expects(:wait_for).with("web", "m2", "suspended", version: nil).returns(true)
        assert_match "m2 in iad: suspended", call(:suspend_app, "resource" => "web", "machine" => "m2")

        FlyApi.any_instance.stubs(:machines).returns([ machine("m3", "stopped") ])
        assert_equal "No machine of web is started, so there is nothing to suspend. describe_resource shows each machine's state.",
                     assert_raises(NativePack::Error) { call(:suspend_app, "resource" => "web") }.message
      end

      test "a cordon takes one named machine out of traffic and an uncordon puts it back" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("m2", "started") ])
        FlyApi.any_instance.expects(:cordon_machine).with("web", "m2").returns({})
        FlyApi.any_instance.expects(:uncordon_machine).with("web", "m2").returns({})

        assert_match "no longer sends requests to m2 of web in iad", call(:cordon_machine, "resource" => "web", "machine" => "m2")
        assert_match "sends requests to m2 of web in iad again", call(:uncordon_machine, "resource" => "web", "machine" => "m2")
        assert_equal "web has no machine m9. describe_resource shows its machines.",
                     assert_raises(NativePack::Error) { call(:cordon_machine, "resource" => "web", "machine" => "m9") }.message
      end

      test "scaling up copies the group's newest machine without its standby, and down destroys stopped machines first, then the newest" do
        older = machine("m1", "started").merge("created_at" => "2026-10-01T10:00:00Z")
        newer = machine("m2", "started").merge("created_at" => "2026-10-02T10:00:00Z")
        newer["config"] = newer["config"].merge("standbys" => [ "m9" ], "env" => { "PORT" => "8080", "FLY_STANDBY_FOR" => "m9" })
        FlyApi.any_instance.stubs(:machines).returns([ older, newer ])
        FlyApi.any_instance.expects(:create_machine).with("web", config: has_entries("image" => "registry.fly.io/web:deployment-42", "env" => { "PORT" => "8080" }), region: "ams")
              .returns("id" => "m3", "region" => "ams", "version" => "v-m3")
        FlyApi.any_instance.expects(:wait_started).with("web", "m3", version: "v-m3").returns(true)

        assert_match "Scaling web from 2 to 3 machines.\nm3 in ams: added, started", call(:scale_app, "resource" => "web", "instances" => 3, "region" => "ams")

        stopped = machine("m4", "stopped").merge("created_at" => "2026-09-01T10:00:00Z")
        FlyApi.any_instance.stubs(:machines).returns([ older, newer, stopped ])
        FlyApi.any_instance.expects(:destroy_machine).with("web", "m4").returns({})
        FlyApi.any_instance.expects(:destroy_machine).with("web", "m2").returns({})
        FlyApi.any_instance.expects(:destroy_machine).with("web", "m1").never
        text = call(:scale_app, "resource" => "web", "instances" => 1)
        assert_match "m4 in iad: destroyed\nm2 in iad: destroyed", text
      end

      test "an app with several process groups is scaled by the group named, and a machine with a volume is not copied" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("w1", "started", group: "worker") ])

        assert_match "runs more than one process group, app and worker", assert_raises(NativePack::Error) { call(:scale_app, "resource" => "web", "instances" => 2) }.message
        assert_match "web (worker) already runs 1 machines", call(:scale_app, "resource" => "web", "instances" => 1, "group" => "worker")

        mounted = machine("m1", "started")
        mounted["config"] = mounted["config"].merge("mounts" => [ { "volume" => "vol_1", "path" => "/data" } ])
        FlyApi.any_instance.stubs(:machines).returns([ mounted ])
        FlyApi.any_instance.expects(:create_machine).never
        assert_match "needs a volume of its own", assert_raises(NativePack::Error) { call(:scale_app, "resource" => "web", "instances" => 2) }.message
      end

      test "a resize gives each machine the size's CPUs and memory, keeps a stopped one stopped, and refuses memory the size cannot take" do
        FlyApi.any_instance.stubs(:machines).returns([ machine("m1", "started"), machine("m2", "stopped") ])
        FlyApi.any_instance.expects(:update_machine).with("web", "m1", config: has_entry("guest", { "cpus" => 2, "cpu_kind" => "performance", "memory_mb" => 4096 }),
                                                          current_version: "v-m1", skip_launch: false).returns("version" => "v-m1-new")
        FlyApi.any_instance.expects(:wait_started).with("web", "m1", version: "v-m1-new").returns(true)
        FlyApi.any_instance.expects(:update_machine).with("web", "m2", has_entry(skip_launch: true)).returns("version" => "v-m2-new")

        text = call(:resize_app, "resource" => "web", "size" => "performance-2x")
        assert_match "m1 in iad: resized, started again", text
        assert_match "m2 in iad: resized, left stopped as it was", text

        assert_match "1 shared CPUs take 256 to 2048 MB of memory in steps of 256, so 4096 MB does not fit m1",
                     assert_raises(NativePack::Error) { call(:resize_app, "resource" => "web", "memory_mb" => 4096) }.message
        assert_match "not a size Fly.io offers", assert_raises(NativePack::Error) { call(:resize_app, "resource" => "web", "size" => "huge") }.message
      end

      test "a cluster's slow queries are read over the range, and its running ones in each of its databases" do
        FlyApi.any_instance.expects(:postgres_slow_queries).with("pg1", range: 7200).returns([
          { "database" => "app", "user" => "web", "calls" => 1200, "total_exec_time_seconds" => 340.5, "mean_exec_time_seconds" => 0.28,
            "max_exec_time_seconds" => 4.2, "query" => "SELECT * FROM orders WHERE id = $1" }
        ])
        slow = call(:postgres_queries, "resource" => "main-db", "minutes" => 120)
        assert_match "within the last 120 minutes", slow
        assert_match "app as web, 1200 calls, 340.5 s in all, mean 280.0 ms, longest 4.2 s, SELECT * FROM orders WHERE id = $1", slow

        FlyApi.any_instance.stubs(:postgres_databases).with("pg1").returns([ { "name" => "app" }, { "name" => "jobs" } ])
        FlyApi.any_instance.stubs(:postgres_active_queries).with("pg1", database: "app").returns([
          { "pid" => 42, "user" => "web", "duration_seconds" => 12.5, "state" => "active", "state_duration_seconds" => 12.5,
            "wait_event_type" => "Lock", "wait_event" => "transactionid", "query" => "UPDATE orders SET paid = true" }
        ])
        FlyApi.any_instance.stubs(:postgres_active_queries).with("pg1", database: "jobs").raises(FlyApi::Error, "Fly answered 500: unable to load active queries")
        active = call(:postgres_queries, "resource" => "pg1", "kind" => "active")
        assert_match "pid 42, web, running 12.5 s, active for 12.5 s, waiting on Lock transactionid, UPDATE orders SET paid = true", active
        assert_match "jobs: could not be read: Fly answered 500", active
        assert_match "is an app", assert_raises(NativePack::Error) { call(:postgres_queries, "resource" => "web") }.message
      end

      test "the organization goes on the map with each app's machines, the hostnames it serves and the clusters it uses" do
        FlyApi.any_instance.stubs(:machines).with("web").returns([ machine("m1", "started"), machine("m2", "started", region: "ams") ])
        FlyApi.any_instance.stubs(:certificates).with("web").returns(Integrations::Pages::Read.new(items: [ { "hostname" => "app.acme.dev" } ], complete: true))

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
        FlyApi.any_instance.stubs(:certificates).returns(Integrations::Pages::Read.new(items: [], complete: false))
        FlyApi.any_instance.stubs(:postgres_clusters).raises(FlyApi::Error, "Fly answered 404: not found")

        snapshot = @pack.map_of(@row)

        assert_equal [ [ "The machines of web could not be read: Fly answered 403: forbidden.", [] ],
                       [ "Only the first 0 certificates of web were read.", [ ResourceMap::KIND_DOMAIN ] ],
                       [ "Managed Postgres clusters could not be read: Fly answered 404: not found.", [ ResourceMap::KIND_DATABASE ] ] ],
                     snapshot.gaps.map { |gap| [ gap.text, gap.kinds ] }
        assert_equal [ ResourceMap::KIND_DOMAIN, ResourceMap::KIND_DATABASE ], snapshot.unread_kinds, "a list cut short or refused takes nothing off the map"
      end

      test "an app's plain environment is read by value and its secrets by name, and nothing of a value is kept" do
        env = { "REDIS_URL" => "redis://default:fly-redis-pw@cache.internal:6379", "PORT" => "8080" }
        FlyApi.any_instance.stubs(:machines).with("web").returns([ machine("m1", "started").deep_merge("config" => { "env" => env }) ])
        FlyApi.any_instance.stubs(:certificates).returns(Integrations::Pages::Read.new(items: [], complete: true))
        FlyApi.any_instance.stubs(:secret_names).with("web").returns(%w[DATABASE_URL SECRET_KEY_BASE])

        snapshot = @pack.map_of(@row)

        uses = snapshot.uses.index_by(&:variable)
        assert_equal %w[DATABASE_URL REDIS_URL], uses.keys.sort
        assert_equal [ "redis", 6379 ], [ uses["REDIS_URL"].scheme, uses["REDIS_URL"].port ]
        assert_nil uses["DATABASE_URL"].fingerprint, "a secret is known by its name only"
        assert_equal [ "fly", "acme", ResourceMap::KIND_SERVICE, "web" ], uses["REDIS_URL"].from
        ResourceMap.record!(@row, snapshot)
        assert_no_setting_values(snapshot, env["REDIS_URL"], "fly-redis-pw", "cache.internal")
      end

      test "secret names Fly refuses, or asks Firefight to slow down for, are a settings gap that holds nothing back" do
        FlyApi.any_instance.stubs(:app_list).returns(Integrations::Pages::Read.new(items: [ { "name" => "web" }, { "name" => "api" } ], complete: true))
        FlyApi.any_instance.stubs(:machines).returns([])
        FlyApi.any_instance.stubs(:certificates).returns(Integrations::Pages::Read.new(items: [], complete: true))
        FlyApi.any_instance.stubs(:secret_names).with("web").raises(FlyApi::Error.new("Fly answered 429: slow down").extend(Integrations::RateLimited))
        FlyApi.any_instance.expects(:secret_names).with("api").never

        snapshot = @pack.map_of(@row)

        assert_equal [ [ "Fly.io asked Firefight to slow down, so the secret names of web and the apps after it were not read.", [], true ] ],
                     snapshot.gaps.map { |gap| [ gap.text, gap.kinds, gap.settings ] }
        assert snapshot.complete?
        assert_not snapshot.settings_complete?
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

      test "a change re-reads only the app it names with its links, and an app Fly no longer has goes" do
        FlyApi.any_instance.stubs(:app).with("web").returns("name" => "web", "status" => "suspended")
        FlyApi.any_instance.stubs(:machines).with("web").returns([ machine("m1", "stopped") ])
        FlyApi.any_instance.stubs(:certificates).with("web").returns(Integrations::Pages::Read.new(items: [ { "hostname" => "app.acme.dev" } ], complete: true))
        scope = ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "web")

        snapshot = @pack.map_refresh(@row, scope)

        assert_equal [ [ "web", "suspended" ], [ "app.acme.dev", nil ] ], snapshot.resources.map { |found| [ found.external_id, found.status ] },
                     "the cluster it is attached to is read for the link, not written"
        assert_equal [ [ "app.acme.dev", ResourceMap::RELATION_SERVED_BY, "web" ], [ "web", ResourceMap::RELATION_USES, "pg1" ] ],
                     snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }

        FlyApi.any_instance.stubs(:app).with("old").raises(FlyApi::NotFound, "Fly answered 404: app not found")
        assert_equal [ [ "fly", "acme", ResourceMap::KIND_SERVICE, "old" ] ], @pack.map_refresh(@row, scope.with(external_id: "old")).gone
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_DATABASE, external_id: "pg1")), "a cluster is read at the sweep"
      end

      test "deploy history reads a release from when it was made to when it last changed, once it no longer runs" do
        FlyApi.any_instance.stubs(:releases).returns([
          { "id" => "r41", "version" => 41, "status" => "complete", "createdAt" => "2026-09-30T10:00:00Z", "updatedAt" => "2026-09-30T10:02:30Z" },
          { "id" => "r42", "version" => 42, "status" => "running", "createdAt" => "2026-10-01T10:00:00Z", "updatedAt" => "2026-10-01T10:01:00Z" }
        ])

        runs = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "web" }))

        assert_equal [ [ "42", "running", nil ], [ "41", "succeeded", 150 ] ], runs.map { |run| [ run.number, run.status, run.seconds ] }
        assert runs.second.named?("#41")
        assert runs.second.named?("v41")
        assert_not runs.second.named?("v4")
        assert_equal "https://fly.io/apps/web/monitoring", runs.first.url
      end

      test "one release is read by its id or version, paging past the newest, and one Fly does not have is said in words" do
        newest = { "nodes" => [ { "id" => "r60", "version" => 60, "status" => "running", "createdAt" => "2026-10-01T10:00:00Z", "updatedAt" => "2026-10-01T10:01:00Z" } ],
                   "pageInfo" => { "hasNextPage" => true, "endCursor" => "c1" } }
        older = { "nodes" => [ { "id" => "r12", "version" => 12, "status" => "failed", "createdAt" => "2026-08-01T10:00:00Z", "updatedAt" => "2026-08-01T10:03:00Z",
                                 "description" => "Deploy image" } ],
                  "pageInfo" => { "hasNextPage" => false, "endCursor" => nil } }
        FlyApi.any_instance.stubs(:graphql).with(FlyApi::RELEASE_PAGE_QUERY, has_entries("after" => nil)).returns("app" => { "releases" => newest })
        FlyApi.any_instance.stubs(:graphql).with(FlyApi::RELEASE_PAGE_QUERY, has_entries("after" => "c1")).returns("app" => { "releases" => older })

        run = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "web", "run" => "v12" })).sole

        assert_equal [ "r12", "12", "failed", 180, "https://fly.io/apps/web/monitoring" ], [ run.id, run.number, run.status, run.seconds, run.url ]
        assert_equal "r60", Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "web", "run" => "r60" })).sole.id
        assert_match "web has no release 99 among its newest 200",
                     assert_raises(NativePack::Error) { @pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "web", "run" => "99" }) }.message
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
