require "test_helper"

module Integrations
  module Packs
    # One Northflank connection reading several projects, or every one its token can read.
    class NorthflankProjectsTest < ActiveSupport::TestCase
      ALL = IntegrationProvider::ConnectField::ALL

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
        @row = @integration.integration_environments.create!
        Northflank.store_credentials!(@row, Northflank::API_TOKEN => "nf-token")
        @row.store_fields!(Northflank::PROJECT => %w[faylee acme])
        NorthflankApi.any_instance.stubs(:projects).returns(listed([ { "id" => "faylee", "name" => "Faylee" }, { "id" => "acme", "name" => "Acme" } ]))
        %w[faylee acme].each do |project|
          NorthflankApi.any_instance.stubs(:services).with(project).returns(listed([ { "id" => "web" } ]))
          NorthflankApi.any_instance.stubs(:service).with(project, "web").returns(
            "id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/labs/#{project}/web", "status" => { "deployment" => { "status" => "COMPLETED" } }
          )
          NorthflankApi.any_instance.stubs(:addons).with(project).returns(listed([]))
          NorthflankApi.any_instance.stubs(:jobs).with(project).returns(listed([]))
          NorthflankApi.any_instance.stubs(:secret_groups).with(project).returns(listed([]))
        end
      end

      test "several projects go on the map without merging a service two of them call web, each named with its project" do
        snapshot = Northflank.new(@integration).map_of(@row)

        webs = snapshot.resources.select { |found| found.external_id == "web" }
        assert_equal %w[labs/faylee labs/acme], webs.map(&:account)
        assert_equal %w[faylee acme], webs.map { |found| found.details[ResourceMap::SCOPE] }
        assert_equal %w[Faylee Acme], webs.map { |found| found.details[ResourceMap::SCOPE_NAME] }
        assert snapshot.complete?

        ResourceMap.record!(@row, snapshot)
        on_map = ResourceMap::Resource.where(workspace: @workspace, provider: "northflank", external_id: "web").order(:account)
        assert_equal [ "web in Acme", "web in Faylee" ], on_map.map(&:scoped_name)
      end

      test "a connection that reaches one project names nothing with it, as before" do
        @row.store_fields!(Northflank::PROJECT => %w[faylee])

        web = Northflank.new(@integration).map_of(@row).resources.find { |found| found.external_id == "web" }

        assert_nil web.details[ResourceMap::SCOPE]
      end

      test "every project the token can read is listed at each sweep, so one added since is read the next time" do
        @row.store_fields!(Northflank::PROJECT => [ ALL ])
        assert_equal %w[faylee acme], Northflank.new(@integration).map_of(@row).resources.filter_map { |found| found.details[ResourceMap::SCOPE] }.uniq

        NorthflankApi.any_instance.stubs(:projects).returns(listed([ { "id" => "faylee" }, { "id" => "acme" }, { "id" => "new-one", "name" => "New one" } ]))
        NorthflankApi.any_instance.stubs(:services).with("new-one").returns(listed([]))
        NorthflankApi.any_instance.stubs(:addons).with("new-one").returns(listed([ { "id" => "db", "name" => "db", "status" => "running", "appId" => "/labs/new-one/db" } ]))
        NorthflankApi.any_instance.stubs(:jobs).with("new-one").returns(listed([]))
        NorthflankApi.any_instance.stubs(:secret_groups).with("new-one").returns(listed([]))

        found = Northflank.new(@integration).map_of(@row.reload).resources
        assert_equal "new-one", found.find { |each| each.external_id == "db" }.details[ResourceMap::SCOPE]
        assert_includes Integrations::ConnectionSettings.of(@row.reload).known_scopes, "new-one", "the listing is kept for the tools' parameters"
      end

      test "a project the token can no longer read is a gap naming its kinds, and the other project is still read" do
        NorthflankApi.any_instance.stubs(:services).with("acme").raises(NorthflankApi::Error, "Northflank answered 403: forbidden")

        snapshot = Northflank.new(@integration).map_of(@row)

        assert_equal %w[labs/faylee], snapshot.resources.select { |found| found.external_id == "web" }.map(&:account)
        assert_equal [ "Project Acme could not be read: Northflank answered 403: forbidden." ], snapshot.gap_texts
        assert_includes snapshot.unread_kinds, ResourceMap::KIND_SERVICE
        assert_not snapshot.complete?, "nothing it held is taken as gone"
      end

      test "a call finds its project from the resource it names on the map, and one that two projects hold is refused" do
        tool = tool_named("search_logs")
        mapped("web", "faylee")
        NorthflankApi.any_instance.expects(:logs).with("faylee", "services", "web", anything).returns([])

        Integrations::NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "resource" => "web" })

        mapped("web", "acme")
        error = assert_raises(Integrations::Scopes::Unresolved) { Integrations::NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "resource" => "web" }) }
        assert_equal "web is in more than one project Faylee (Northflank) reaches: faylee and acme. Name the project with project.", error.message
      end

      test "a call that names no resource on the map and no project is refused with the projects to choose from" do
        error = assert_raises(NativePack::Error) do
          Integrations::NativeExecutor.call(tool: tool_named("search_logs"), environment_row: @row, arguments: { "resource" => "worker" })
        end

        assert_equal "Faylee (Northflank) reaches more than one project: faylee and acme. Name the project with project.", error.message
      end

      test "a project the connection does not reach is refused before anything is sent" do
        NorthflankApi.any_instance.expects(:request).never

        error = assert_raises(Integrations::Scopes::Unresolved) do
          Integrations::NativeExecutor.call(tool: tool_named("api_request"), environment_row: @row, arguments: { "method" => "POST", "path" => "services/web/restart", "project" => "other" })
        end
        assert_equal "Faylee (Northflank) does not reach project other. It reaches projects faylee and acme.", error.message
      end

      test "a change through the API reaches only the project its path's service is in" do
        mapped("web", "acme")
        NorthflankApi.any_instance.expects(:request).with("POST", "acme", "services/web/restart", nil).returns({})

        Integrations::NativeExecutor.call(tool: tool_named("api_request"), environment_row: @row, arguments: { "method" => "POST", "path" => "services/web/restart" })
      end

      test "a restart asked of a resource on the map runs in the project it lives in, and the confirmation names it" do
        tool_named("api_request").update!(enabled: true)
        resource = mapped("web", "acme")

        call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::RESTART, { "resource" => resource.id }, principal: workspace_memberships(:alice_workspace_one))

        assert_equal "acme", call.arguments["project"]
        assert_equal "Faylee (Northflank), project acme", @integration.target_label(@row, scope: call.arguments["project"])
      end

      test "the tools take the project, offered from the projects the connection reaches, only when it reaches several" do
        tool = tool_named("search_logs")
        Integrations::ConnectionSettings.of(@row).scope_options

        project = tool.offered_schema.dig("properties", "project")
        assert_equal %w[faylee acme], project["enum"]
        assert_match "faylee (Faylee), acme (Acme)", project["description"]

        @row.store_fields!(Northflank::PROJECT => %w[faylee])
        assert_nil tool.reload.offered_schema.dig("properties", "project")
      end

      test "listing resources without a project lists every project's, each headed with its own" do
        text = Northflank.new(@integration).call("list_resources", environment_row: @row, arguments: {})["content"].sole["text"]

        assert_match "Project faylee, 1 services and databases.", text
        assert_match "Project acme, 1 services and databases.", text
      end

      test "a notification about a service is read again in the project the map has it in" do
        mapped("web", "acme")
        NorthflankApi.any_instance.expects(:service).with("acme", "web").returns(
          "id" => "web", "name" => "web", "serviceType" => "combined", "appId" => "/labs/acme/web", "status" => { "deployment" => { "status" => "FAILED" } }
        )

        web = Northflank.new(@integration).map_refresh(@row, ResourceMap::Scope.new(external_id: "web")).resources.sole

        assert_equal [ "labs/acme", "failed" ], [ web.account, web.status ]
      end

      test "the webhook covers every project the connection reaches, and is registered again once that changes" do
        NorthflankApi.any_instance.stubs(:notifications).returns(listed([]))
        NorthflankApi.any_instance.expects(:create_notification).with(has_entries(projects: %w[faylee acme])).returns("id" => "nf-1")

        webhook = MapEventSources::Northflank.register(@row, url: "https://firefight.example.com/api/v1/map_events/t")
        @row.update!(map_events_webhook_id: webhook.id, map_events_scopes: webhook.scopes)
        assert_not MapEvents.scopes_changed?(@row)

        @row.store_fields!(Northflank::PROJECT => %w[faylee])
        assert MapEvents.scopes_changed?(@row.reload)
      end

      test "a project id on the connect form is checked with the token, and every project it can read needs at least one" do
        NorthflankApi.any_instance.stubs(:project).with("faylee").returns({})
        NorthflankApi.any_instance.stubs(:project).with("gone").raises(NorthflankApi::NotFound, "Northflank answered 404: not found")

        assert_nil Northflank.credential_refusal({ Northflank::API_TOKEN => "nf" }, fields: { Northflank::PROJECT => %w[faylee] })
        assert_match "project gone", Northflank.credential_refusal({ Northflank::API_TOKEN => "nf" }, fields: { Northflank::PROJECT => %w[faylee gone] })
        assert_nil Northflank.credential_refusal({ Northflank::API_TOKEN => "nf" }, fields: { Northflank::PROJECT => [ ALL ] })
        assert_equal [ %w[faylee Faylee] ], Northflank.scope_options({ Northflank::API_TOKEN => "nf" }).first(1).map { |option| [ option.value, option.label ] }
        NorthflankApi.any_instance.stubs(:projects).returns(listed([]))
        assert_match "can read no Northflank projects", Northflank.credential_refusal({ Northflank::API_TOKEN => "nf" }, fields: { Northflank::PROJECT => [ ALL ] })
      end

      private

      def listed(items) = Pages::Read.new(items: items, complete: true)

      def tool_named(name)
        @integration.tools.find_or_create_by!(name: name) do |tool|
          definition = Northflank.tool_definitions.find { |each| each.name == name }
          tool.assign_attributes(params_schema: definition.params_schema, read_only: definition.read_only, enabled: true)
        end
      end

      def mapped(name, project)
        ResourceMap::Resource.create!(workspace: @workspace, integration_environment: @row, provider: "northflank", account: "labs/#{project}",
                                      kind: ResourceMap::KIND_SERVICE, external_id: name, name: name, details: { ResourceMap::SCOPE => project },
                                      first_seen_at: Time.current, last_seen_at: Time.current)
      end
    end
  end
end
