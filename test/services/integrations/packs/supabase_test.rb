require "test_helper"

module Integrations
  module Packs
    class SupabaseTest < ActiveSupport::TestCase
      PARENT = "abcdefghijklmnopqrst".freeze
      BRANCH = "zyxwvutsrqponmlkjihg".freeze
      # Action runs as the Management API answers them (ActionRunResponse), the newest first.
      STEPS = %w[clone pull health configure migrate seed deploy].freeze
      NEWEST = { "id" => "run_new", "branch_id" => "b2", "check_run_id" => 42, "created_at" => "2026-10-20T09:00:00Z",
                 "run_steps" => STEPS.map { |name| { "name" => name, "status" => "EXITED", "created_at" => "2026-10-20T09:00:00Z", "updated_at" => "2026-10-20T09:03:00Z" } } }.freeze
      OLDER = { "id" => "run_old", "branch_id" => "b2", "check_run_id" => 41, "created_at" => "2026-10-19T09:00:00Z",
                "run_steps" => [ { "name" => "clone", "status" => "EXITED", "updated_at" => "2026-10-19T09:01:00Z" },
                                 { "name" => "migrate", "status" => "DEAD", "updated_at" => "2026-10-19T09:02:00Z" } ] }.freeze
      # A scrape in the Prometheus text format, with the names supabase/supabase-grafana's docs/metrics.md lists.
      SCRAPE = <<~TEXT.freeze
        # HELP node_memory_MemTotal_bytes Memory information field MemTotal_bytes.
        node_memory_MemTotal_bytes{supabase_project_ref="#{PARENT}",service_type="db"} 1000
        node_memory_MemAvailable_bytes{supabase_project_ref="#{PARENT}",service_type="db"} 250
        node_filesystem_size_bytes{supabase_project_ref="#{PARENT}",service_type="db",mountpoint="/data"} 200
        node_filesystem_avail_bytes{supabase_project_ref="#{PARENT}",service_type="db",mountpoint="/data"} 50
        node_cpu_seconds_total{supabase_project_ref="#{PARENT}",service_type="db",cpu="0",mode="idle"} 100
        node_cpu_seconds_total{supabase_project_ref="#{PARENT}",service_type="db",cpu="0",mode="user"} 100
        node_load1{supabase_project_ref="#{PARENT}",service_type="db"} 0.42
      TEXT

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "supabase", name: "Supabase",
                                                       settings: { "server_url" => "https://mcp.supabase.com/mcp?read_only=false",
                                                                   Integration::FIELDS_SETTING => { "read_only" => "false" } })
        @row = @integration.integration_environments.create!(credentials: IntegrationEnvironment.token_credentials("Bearer sbp_token"))
        @pack = Supabase.new(@integration)
        database = ResourceMap::Found.new(provider: "supabase", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: PARENT, name: "shop")
        branch = ResourceMap::Found.new(provider: "supabase", account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: BRANCH, name: "shop/feature")
        ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ database, branch ],
                                                            links: [ ResourceMap::FoundLink.new(from: branch.key, to: database.key, relation: ResourceMap::RELATION_BRANCH_OF) ]))
      end

      test "a connection made read only is offered no change, as the server leaves out its own" do
        settings = ConnectionSettings.of(@row)
        assert Supabase.tool_definitions.all? { |definition| Supabase.offers?(settings, definition) }

        @integration.update!(settings: @integration.settings.merge(Integration::FIELDS_SETTING => { "read_only" => "true" }))
        offered = Supabase.tool_definitions.select { |definition| Supabase.offers?(ConnectionSettings.of(@row.reload), definition) }
        assert offered.all?(&:read_only)
        assert_equal %w[restart_project restore_to_point_in_time], Supabase.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "action runs read the newest one's end from its branch's status, an older one from its steps, each linking its branch's page" do
        SupabaseApi.any_instance.expects(:action_runs).with(BRANCH, limit: 20).returns([ NEWEST, OLDER ])
        SupabaseApi.any_instance.expects(:branches).with(PARENT).returns([ { "project_ref" => BRANCH, "status" => "MIGRATIONS_FAILED", "latest_check_run_id" => 42,
                                                                            "git_branch" => "feature" } ])

        result = call(:list_action_runs, "project_id" => BRANCH)
        newest, older = Capabilities::History.runs_of(result)

        assert_equal [ "run_new", Capabilities::History::FAILED, 180 ], [ newest.id, newest.status, newest.seconds ]
        assert_match "branch migrations failed", newest.detail
        assert_equal [ Capabilities::History::FAILED, "feature, stopped at migrate" ], [ older.status, older.detail ]
        assert_equal "https://supabase.com/dashboard/project/#{BRANCH}/branches", newest.url
      end

      test "one action run has its steps as parts, each reading the run's log" do
        SupabaseApi.any_instance.expects(:action_run).with(BRANCH, "run_old").returns(OLDER)
        SupabaseApi.any_instance.stubs(:branches).returns([])

        run = Capabilities::History.runs_of(call(:get_action_run, "project_id" => BRANCH, "run_id" => "run_old")).sole
        failed = run.first_failed_part
        assert_equal "migrate", failed.name
        assert_equal({ "tool" => "get_action_run_logs", "arguments" => { "project_id" => BRANCH, "run_id" => "run_old" } }, failed.log)
      end

      test "a run's log is cut to its last lines and filtered by text" do
        SupabaseApi.any_instance.stubs(:action_run_logs).returns("starting\nApplying migration 20261020_add_index\nERROR: relation exists\ndone\n")

        text = call(:get_action_run_logs, "project_id" => BRANCH, "run_id" => "run_old", "text" => "migration")["content"].sole["text"]
        assert_match "What action run run_old of #{BRANCH} printed.\nApplying migration 20261020_add_index", text
        assert_no_match(/relation exists/, text)
      end

      test "health reads the project with each service, saying which are not healthy" do
        SupabaseApi.any_instance.stubs(:project).returns({ "name" => "shop", "status" => "ACTIVE_HEALTHY", "region" => "eu-west-1", "database" => { "version" => "15.8" } })
        SupabaseApi.any_instance.stubs(:health).returns([ { "name" => "db", "status" => "ACTIVE_HEALTHY" },
                                                         { "name" => "auth", "status" => "UNHEALTHY", "error" => "connection refused" } ])

        text = call(:get_project_health, "project_id" => PARENT)["content"].sole["text"]
        assert_match "How shop stands on Supabase now: status ACTIVE_HEALTHY, region eu-west-1, Postgres 15.8. 1 of 2 services are not healthy.", text
        assert_match "- auth: UNHEALTHY, connection refused", text
      end

      test "metrics read memory and each disk from one scrape, CPU from two, and any other by its name" do
        later = SCRAPE.sub('mode="idle"} 100', 'mode="idle"} 130').sub('mode="user"} 100', 'mode="user"} 110')
        SupabaseApi.any_instance.stubs(:metrics).returns(SCRAPE).then.returns(later)
        @pack.stubs(:sleep)

        result = call(:get_project_metrics, "project_id" => PARENT, "readings" => Supabase::READINGS, "names" => [ "node_load1" ])
        text = result["content"].sole["text"]

        charts = result[Telemetry::STRUCTURED][Telemetry::CHARTS]
        assert_equal({ "cpu of #{PARENT}" => 25.0, "memory of #{PARENT}" => 75.0, "disk of #{PARENT}" => 75.0 },
                     charts.to_h { |chart| [ chart["title"], chart["series"].sole["points"].sole.last ] })
        assert_match "node_load1: service_type=db 0.42", text
        error = assert_raises(NativePack::Error) { call(:get_project_metrics, "project_id" => PARENT, "readings" => [ "network" ]) }
        assert_match "not network", error.message
      end

      test "a restore to a moment needs point in time recovery on, and a connection scoped to a project reaches only that one" do
        SupabaseApi.any_instance.stubs(:backups).returns({ "pitr_enabled" => false, "backups" => [] })
        error = assert_raises(NativePack::Error) { call(:restore_to_point_in_time, "project_id" => PARENT, "to" => "2026-10-20T09:00:00Z") }
        assert_match "Point in time recovery is off", error.message

        SupabaseApi.any_instance.stubs(:backups).returns({ "pitr_enabled" => true })
        SupabaseApi.any_instance.expects(:restore_to).with(PARENT, Time.zone.parse("2026-10-20T09:00:00Z")).returns({})
        text = call(:restore_to_point_in_time, "project_id" => PARENT, "to" => "2026-10-20T09:00:00Z")["content"].sole["text"]
        assert_match "Supabase is restoring #{PARENT}'s database to 2026-10-20T09:00:00Z.", text
        assert text.end_with?("https://supabase.com/dashboard/project/#{PARENT}/database/backups/pitr")

        @integration.update!(settings: @integration.settings.merge(Integration::FIELDS_SETTING => { "project_ref" => PARENT, "read_only" => "false" }))
        error = assert_raises(PolicyRefusal) { call(:restart_project, "project_id" => BRANCH) }
        assert_match "scoped to project #{PARENT}", error.message
      end

      private

      def call(tool, arguments) = @pack.call(tool.to_s, environment_row: @row.reload, arguments: arguments)
    end
  end
end
