require "test_helper"

module Integrations
  module Packs
    # One Render connection reading several workspaces, or every one its API key can read.
    class RenderWorkspacesTest < ActiveSupport::TestCase
      ALL = IntegrationProvider::ConnectField::ALL
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "render", name: "Shops")
        @row = @integration.integration_environments.create!
        Render.store_credentials!(@row, Render::API_KEY => "rnd_key")
        @row.store_fields!(Render::WORKSPACE => %w[tea-a tea-b])
        RenderApi.any_instance.stubs(:owners).returns(listed([ owner("tea-a", "Acme"), owner("tea-b", "Billing"), { "id" => "usr-1", "name" => "Me", "type" => "user" } ]))
        { "tea-a" => "srv-a", "tea-b" => "srv-b" }.each do |workspace, id|
          RenderApi.any_instance.stubs(:services).with(workspace).returns(listed([ { "id" => id, "name" => "web", "type" => "background_worker", "ownerId" => workspace, "serviceDetails" => {} } ]))
          RenderApi.any_instance.stubs(:postgres_databases).with(workspace).returns(listed([]))
          RenderApi.any_instance.stubs(:key_values).with(workspace).returns(listed([]))
        end
        RenderApi.any_instance.stubs(:deploys).returns([])
        RenderApi.any_instance.stubs(:env_vars).returns(listed([]))
        RenderApi.any_instance.stubs(:env_groups).returns([])
      end

      test "several workspaces go on the map without merging two services called web, each named with its workspace" do
        webs = Render.new(@integration).map_of(@row).resources.select { |found| found.name == "web" }

        assert_equal %w[tea-a tea-b], webs.map(&:account)
        assert_equal [ %w[tea-a Acme], %w[tea-b Billing] ], webs.map { |found| found.details.values_at(ResourceMap::SCOPE, ResourceMap::SCOPE_NAME) }
      end

      test "every workspace the key can read is listed at each sweep, a team's only, so one added since is read the next time" do
        @row.store_fields!(Render::WORKSPACE => [ ALL ])
        assert_equal [ %w[tea-a Acme], %w[tea-b Billing] ], Render.scope_options({ Render::API_KEY => "k" }).map { |option| [ option.value, option.label ] }

        RenderApi.any_instance.stubs(:owners).returns(listed([ owner("tea-a", "Acme"), owner("tea-b", "Billing"), owner("tea-c", "Docs") ]))
        RenderApi.any_instance.stubs(:services).with("tea-c").returns(listed([]))
        RenderApi.any_instance.stubs(:postgres_databases).with("tea-c").returns(listed([ { "id" => "dpg-c", "name" => "db", "status" => "available" } ]))
        RenderApi.any_instance.stubs(:key_values).with("tea-c").returns(listed([]))

        assert_equal "tea-c", Render.new(@integration).map_of(@row.reload).resources.find { |found| found.external_id == "dpg-c" }.account
      end

      test "a call finds its workspace from the resource it names on the map, and a name two workspaces hold is refused" do
        tool = tool_named("search_logs")
        mapped("srv-a", "tea-a")
        RenderApi.any_instance.expects(:logs).with(has_entries("ownerId" => "tea-a", "resource" => "srv-a")).returns("logs" => [], "hasMore" => false)

        NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "resource" => "web" })

        mapped("srv-b", "tea-b")
        error = assert_raises(Scopes::Unresolved) { NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "resource" => "web" }) }
        assert_match "more than one workspace Shops (Render) reaches: tea-a and tea-b", error.message
      end

      test "a restart reaches only the workspace the service lives in" do
        mapped("srv-b", "tea-b")
        RenderApi.any_instance.expects(:services).with("tea-a").never
        RenderApi.any_instance.expects(:restart_service).with("srv-b").returns({})

        NativeExecutor.call(tool: tool_named("restart_service"), environment_row: @row, arguments: { "resource" => "web" })
      end

      test "a change Render names by service alone is read in the workspace the map, or Render, says owns it" do
        RenderApi.any_instance.stubs(:service).with("srv-b").returns("id" => "srv-b", "name" => "web", "type" => "background_worker", "ownerId" => "tea-b", "serviceDetails" => {})

        snapshot = Render.new(@integration).map_refresh(@row, ResourceMap::Scope.new(external_id: "srv-b"))

        assert_equal "tea-b", snapshot.resources.sole.account
      end

      test "each workspace gets its own webhook with the secret Render makes, and narrowing takes back the dropped one's" do
        RenderApi.any_instance.stubs(:webhooks).returns(listed([]))
        RenderApi.any_instance.expects(:create_webhook).with("tea-a", has_entries(url: URL)).returns("id" => "whk-a", "secret" => "whsec_a")
        RenderApi.any_instance.expects(:create_webhook).with("tea-b", has_entries(url: URL)).returns("id" => "whk-b", "secret" => "whsec_b")

        webhook = MapEventSources::Render.register(@row, url: URL)
        assert_equal({ "tea-a" => "whk-a", "tea-b" => "whk-b" }, JSON.parse(webhook.id))
        assert_equal "whsec_a\nwhsec_b", webhook.secret

        @row.update!(map_events_webhook_id: webhook.id)
        @row.store_fields!(Render::WORKSPACE => %w[tea-b])
        RenderApi.any_instance.unstub(:create_webhook)
        RenderApi.any_instance.stubs(:webhooks).with("tea-b").returns(listed([ { "id" => "whk-b", "url" => URL, "enabled" => true, "secret" => "whsec_b" } ]))
        RenderApi.any_instance.expects(:delete_webhook).with("whk-a").returns({})
        assert_equal({ "tea-b" => "whk-b" }, JSON.parse(MapEventSources::Render.register(@row.reload, url: URL).id))
      end

      test "the person is asked before Firefight's webhook would be a workspace's only one, naming each such workspace" do
        RenderApi.any_instance.stubs(:webhooks).returns(listed([]))
        ConnectionSettings.of(@row).scope_options

        assert_match "Render workspaces Acme and Billing have no webhooks yet. On Render's Pro plan", MapEventSources::Render.confirmation_for(@row.reload, url: URL)
      end

      private

      def listed(items) = Pages::Read.new(items: items, complete: true)

      def owner(id, name) = { "id" => id, "name" => name, "type" => "team" }

      def tool_named(name)
        definition = Render.tool_definitions.find { |each| each.name == name }
        @integration.tools.create!(name: name, params_schema: definition.params_schema, read_only: definition.read_only, enabled: true)
      end

      def mapped(id, workspace)
        ResourceMap::Resource.create!(workspace: @workspace, integration_environment: @row, provider: "render", account: workspace, kind: ResourceMap::KIND_SERVICE,
                                      external_id: id, name: "web", details: { ResourceMap::SCOPE => workspace }, first_seen_at: Time.current, last_seen_at: Time.current)
      end
    end
  end
end
