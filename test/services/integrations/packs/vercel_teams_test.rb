require "test_helper"

module Integrations
  module Packs
    # One Vercel connection reading several teams, or every one its token can reach, and none still reading the token's own.
    class VercelTeamsTest < ActiveSupport::TestCase
      ALL = IntegrationProvider::ConnectField::ALL
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "vercel", name: "Sites")
        @row = @integration.integration_environments.create!
        Vercel.store_credentials!(@row, Vercel::API_TOKEN => "tok")
        @row.store_fields!(Vercel::TEAM => %w[team_a team_b])
        @lister = api_for(nil)
        @lister.stubs(:teams).returns(listed([ { "id" => "team_a", "slug" => "acme", "name" => "Acme" }, { "id" => "team_b", "slug" => "blog", "name" => "Blog" } ]))
        @apis = %w[team_a team_b].to_h do |team|
          api = api_for(team)
          api.stubs(:projects).returns(listed([ { "id" => "prj_#{team}", "name" => "shop", "accountId" => team } ]))
          api.stubs(:project_env).returns([ [], false ])
          api.stubs(:project_domains).returns(listed([]))
          api.stubs(:team).returns("slug" => team)
          [ team, api ]
        end
      end

      test "several teams go on the map without merging two projects called shop, each named with its team" do
        shops = Vercel.new(@integration).map_of(@row).resources.select { |found| found.name == "shop" }

        assert_equal %w[team_a team_b], shops.map(&:account)
        assert_equal [ %w[team_a Acme], %w[team_b Blog] ], shops.map { |found| found.details.values_at(ResourceMap::SCOPE, ResourceMap::SCOPE_NAME) }
      end

      test "every team the token can reach is listed at each sweep, so one joined since is read the next time" do
        @row.store_fields!(Vercel::TEAM => [ ALL ])
        @lister.stubs(:teams).returns(listed([ { "id" => "team_a", "name" => "Acme" }, { "id" => "team_c", "name" => "Docs" } ]))
        docs = api_for("team_c")
        docs.stubs(:projects).returns(listed([ { "id" => "prj_docs", "name" => "docs", "accountId" => "team_c" } ]))
        docs.stubs(:project_env).returns([ [], false ])
        docs.stubs(:project_domains).returns(listed([]))
        docs.stubs(:team).returns("slug" => "docs")

        assert_equal "team_c", Vercel.new(@integration).map_of(@row).resources.find { |found| found.external_id == "prj_docs" }.account
      end

      test "a team left empty reads the token's own account as before, with nothing to choose" do
        @row.store_fields!({})
        own = api_for(nil)
        own.stubs(:projects).returns(listed([ { "id" => "prj_own", "name" => "site", "accountId" => "team_own" } ]))
        own.stubs(:project_env).returns([ [], false ])
        own.stubs(:project_domains).returns(listed([]))
        own.stubs(:user).returns("username" => "me")

        site = Vercel.new(@integration).map_of(@row).resources.find { |found| found.external_id == "prj_own" }
        assert_nil site.details[ResourceMap::SCOPE]
        assert_nil Scopes.argument(@integration.reload)
      end

      test "a call finds its team from the project it names on the map, a name two teams hold is refused, and a change stays in its team" do
        mapped("prj_team_b", "team_b")
        @apis["team_b"].expects(:deployments).with("prj_team_b", has_entries(limit: 20)).returns([])
        @apis["team_a"].expects(:deployments).never

        NativeExecutor.call(tool: tool_named("list_deployments"), environment_row: @row, arguments: { "resource" => "shop" })

        mapped("prj_team_a", "team_a")
        error = assert_raises(Scopes::Unresolved) { NativeExecutor.call(tool: tool_named("list_deployments"), environment_row: @row, arguments: { "resource" => "shop" }) }
        assert_match "more than one team Sites (Vercel) reaches: team_a and team_b", error.message
      end

      test "a change Vercel names in a team is read in that team" do
        @apis["team_b"].expects(:project).with("prj_team_b").returns("id" => "prj_team_b", "name" => "shop", "accountId" => "team_b")

        snapshot = Vercel.new(@integration).map_refresh(@row, ResourceMap::Scope.new(account: "team_b", kind: ResourceMap::KIND_SITE, external_id: "prj_team_b"))

        assert_equal "team_b", snapshot.resources.find { |found| found.external_id == "prj_team_b" }.account
      end

      test "each team gets its own webhook with the secret Vercel makes, and narrowing takes back the dropped one's" do
        @apis.each_value { |api| api.stubs(:webhooks).returns([]) }
        @apis["team_a"].expects(:create_webhook).returns("id" => "hook_a", "secret" => "sa")
        @apis["team_b"].expects(:create_webhook).returns("id" => "hook_b", "secret" => "sb")

        webhook = MapEventSources::Vercel.register(@row, url: URL)
        assert_equal [ { "team_a" => "hook_a", "team_b" => "hook_b" }, "sa\nsb", %w[team_a team_b] ], [ JSON.parse(webhook.id), webhook.secret, webhook.scopes ]

        @row.update!(map_events_webhook_id: webhook.id)
        @row.store_fields!(Vercel::TEAM => %w[team_b])
        @apis["team_a"].expects(:delete_webhook).with("hook_a").returns({})
        @apis["team_b"].expects(:create_webhook).returns("id" => "hook_b2", "secret" => "sb2")
        assert_equal({ "team_b" => "hook_b2" }, JSON.parse(MapEventSources::Vercel.register(@row.reload, url: URL).id))
      end

      test "the connect form lists the token's teams, and checks each one chosen" do
        assert_equal [ %w[team_a Acme], %w[team_b Blog] ], Vercel.scope_options({ Vercel::API_TOKEN => "tok" }).map { |option| [ option.value, option.label ] }
        @apis["team_a"].stubs(:check!).returns({})
        @apis["team_b"].stubs(:check!).raises(VercelApi::Error, "Vercel answered 403: Not authorized")

        assert_equal "Vercel refused this token or team team_b: Vercel answered 403: Not authorized.",
                     Vercel.credential_refusal({ Vercel::API_TOKEN => "tok" }, fields: { Vercel::TEAM => %w[team_a team_b] })
      end

      private

      def listed(items) = Pages::Read.new(items: items, complete: true)

      def api_for(team)
        api = VercelApi.allocate.tap { |built| built.send(:initialize, "tok", team) }
        VercelApi.stubs(:new).with("tok", team).returns(api)
        VercelApi.stubs(:new).with("tok").returns(api) if team.nil?
        api
      end

      def tool_named(name)
        @integration.tools.find_or_create_by!(name: name) do |tool|
          definition = Vercel.tool_definitions.find { |each| each.name == name }
          tool.assign_attributes(params_schema: definition.params_schema, read_only: definition.read_only, enabled: true)
        end
      end

      def mapped(id, team)
        ResourceMap::Resource.create!(workspace: @workspace, integration_environment: @row, provider: "vercel", account: team, kind: ResourceMap::KIND_SITE,
                                      external_id: id, name: "shop", details: { ResourceMap::SCOPE => team }, first_seen_at: Time.current, last_seen_at: Time.current)
      end
    end
  end
end
