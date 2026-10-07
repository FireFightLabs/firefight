require "test_helper"

module Integrations
  module Packs
    # One Railway connection reading the same environment in several projects, or in every one its token can read.
    class RailwayProjectsTest < ActiveSupport::TestCase
      ALL = IntegrationProvider::ConnectField::ALL

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "railway", name: "Shops")
        @row = @integration.integration_environments.create!
        Railway.store_credentials!(@row, Railway::API_TOKEN => "rw-token")
        @row.store_fields!(Railway::PROJECT => %w[prj-1 prj-2], Railway::ENVIRONMENT => "production")
        RailwayApi.any_instance.stubs(:workspaces).returns([ { "id" => "ws-1", "name" => "Acme" } ])
        RailwayApi.any_instance.stubs(:projects).with("ws-1").returns(listed([ { "id" => "prj-1", "name" => "shop" }, { "id" => "prj-2", "name" => "blog" } ]))
        { "prj-1" => "env-1", "prj-2" => "env-2" }.each do |project, environment|
          RailwayApi.any_instance.stubs(:project).with(project).returns(
            "id" => project, "name" => project, "environments" => { "edges" => [ { "node" => { "id" => environment, "name" => "production" } } ] }
          )
          RailwayApi.any_instance.stubs(:service_instances).with(project, environment).returns(listed([
            { "serviceId" => "svc-web-#{project}", "serviceName" => "web", "latestDeployment" => { "id" => "dep-#{project}", "status" => "SUCCESS" } }
          ]))
        end
        RailwayApi.any_instance.stubs(:service_variables).returns([ {}, {} ])
      end

      test "each project's environment goes on the map under its own account, each web named with its project" do
        snapshot = Railway.new(@integration).map_of(@row)

        webs = snapshot.resources.select { |found| found.name == "web" }
        assert_equal %w[prj-1/env-1 prj-2/env-2], webs.map(&:account)
        assert_equal [ %w[prj-1 shop], %w[prj-2 blog] ], webs.map { |found| found.details.values_at(ResourceMap::SCOPE, ResourceMap::SCOPE_NAME) }
      end

      test "every project the token can read is listed from each workspace its account belongs to" do
        @row.store_fields!(Railway::PROJECT => [ ALL ], Railway::ENVIRONMENT => "production")

        assert_equal %w[prj-1 prj-2], Railway.new(@integration).map_of(@row).resources.filter_map { |found| found.details[ResourceMap::SCOPE] }
        RailwayApi.any_instance.stubs(:workspaces).raises(RailwayApi::Refused, "Railway refused this: Not Authorized")
        RailwayApi.any_instance.stubs(:projects).with(nil).returns(listed([ { "id" => "prj-1", "name" => "shop" } ]))
        assert_equal [ %w[prj-1 shop] ], Railway.scope_options({ Railway::API_TOKEN => "workspace-token" }).map { |option| [ option.value, option.label ] },
                     "a workspace token lists its own workspace's projects"
      end

      test "a project without the environment is refused on the form by name" do
        RailwayApi.any_instance.stubs(:project).with("prj-3").returns("id" => "prj-3", "name" => "docs", "environments" => { "edges" => [] })

        assert_nil Railway.credential_refusal({ Railway::API_TOKEN => "t" }, fields: { Railway::PROJECT => %w[prj-1 prj-2], Railway::ENVIRONMENT => "production" })
        assert_equal "Project docs has no environment called production. It has none.",
                     Railway.credential_refusal({ Railway::API_TOKEN => "t" }, fields: { Railway::PROJECT => %w[prj-1 prj-3], Railway::ENVIRONMENT => "production" })
      end

      test "a change reaches only the project its service lives in on the map" do
        tool = @integration.tools.create!(name: "restart_deployment", read_only: false, enabled: true, params_schema: {})
        ResourceMap::Resource.create!(workspace: @workspace, integration_environment: @row, provider: "railway", account: "prj-2/env-2", kind: ResourceMap::KIND_SERVICE,
                                      external_id: "svc-web-prj-2", name: "web", details: { ResourceMap::SCOPE => "prj-2" }, first_seen_at: Time.current, last_seen_at: Time.current)
        RailwayApi.any_instance.expects(:service_instances).with("prj-1", "env-1").never
        RailwayApi.any_instance.expects(:restart).with("dep-prj-2").returns(true)

        NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "resource" => "web" })
      end

      test "a change in a project the connection does not read changes nothing, and one in a project it reads is read there" do
        RailwayApi.any_instance.expects(:service_instance).with("env-2", "svc-web-prj-2").returns(
          "serviceId" => "svc-web-prj-2", "serviceName" => "web", "latestDeployment" => { "status" => "FAILED" }
        )
        pack = Railway.new(@integration)

        assert_equal "failed", pack.map_refresh(@row, ResourceMap::Scope.new(account: "prj-2/env-2", external_id: "svc-web-prj-2")).resources.first.status
        assert_empty Railway.new(@integration).map_refresh(@row, ResourceMap::Scope.new(account: "prj-9/env-9", external_id: "svc-x")).resources
      end

      test "baselines are read in the project each resource lives in" do
        web = ResourceMap::Resource.new(provider: "railway", account: "prj-2/env-2", kind: ResourceMap::KIND_SERVICE, external_id: "svc-web-prj-2", name: "web",
                                        details: { ResourceMap::SCOPE => "prj-2" })
        RailwayApi.any_instance.expects(:metrics).with(has_entries("serviceId" => "svc-web-prj-2", "environmentId" => "env-2")).returns([])

        Railway.new(@integration).baselines_of(@row, [ web ], 7.days.ago..Time.current)
      end

      private

      def listed(items) = Pages::Read.new(items: items, complete: true)
    end
  end
end
