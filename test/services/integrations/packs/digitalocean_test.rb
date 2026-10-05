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
      end

      test "the token is stored trimmed, a wrong one is said on the form, and only the changes are not read only" do
        assert_equal "dop-token", @row.reload.credentials_hash[Digitalocean::API_TOKEN]
        assert_equal %w[rollback_app restart_app scale_app reboot_droplet], Digitalocean.tool_definitions.reject(&:read_only).map(&:name)
        DigitaloceanApi.any_instance.stubs(:account).raises(DigitaloceanApi::Error, "DigitalOcean answered 401: Unable to authenticate you")
        assert_equal "DigitalOcean refused this token: DigitalOcean answered 401: Unable to authenticate you.",
                     Digitalocean.credential_refusal({ Digitalocean::API_TOKEN => "dop-bad" })
        assert_equal "Paste a personal access token.", Digitalocean.credential_refusal({})
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
        DigitaloceanApi.any_instance.expects(:log_urls).with(APP_ID, type: "RUN_RESTARTED", component: "web").twice.returns([ "https://logs.example/1.log" ])
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

      test "a deployment list names each id, phase and commit, for a rollback" do
        DigitaloceanApi.any_instance.stubs(:deployments).returns([ APP["active_deployment"].merge("id" => "dep-2"),
                                                                    { "id" => "dep-1", "phase" => "SUPERSEDED", "created_at" => "2026-09-30T10:00:00Z" } ])

        text = call(:list_deployments, "resource" => APP_ID)

        assert_match "2026-10-01T10:00:00Z, deployment dep-2, ACTIVE, commit abc pushed to github/acme/shop, commits web abc123456789", text
        assert_match "deployment dep-1, SUPERSEDED", text
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

      test "a rollback goes to the deployment named and says the app is pinned" do
        DigitaloceanApi.any_instance.expects(:rollback).with(APP_ID, "dep-1").returns("deployment" => { "id" => "dep-3" })

        text = call(:rollback_app, "resource" => "shop", "deployment" => "dep-1")

        assert text.start_with?("shop is rolling back to deployment dep-1, as new deployment dep-3. DigitalOcean pins the app")
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

      test "a list read only in part is a gap, and the kinds it holds are not taken as gone" do
        DigitaloceanApi.any_instance.stubs(:droplets).returns(Pages::Read.new(items: [ { "id" => 1, "name" => "one" } ], complete: false))

        snapshot = @pack.map_of(@row)

        assert_includes snapshot.unread_kinds, ResourceMap::KIND_VIRTUAL_MACHINE
        assert_equal [ ResourceMap::Gap.new(text: "Only the first 1 Droplets were read.", kinds: [ ResourceMap::KIND_VIRTUAL_MACHINE ]) ], snapshot.gaps
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
