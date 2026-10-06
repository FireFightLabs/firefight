require "test_helper"

module Mcp
  module Tools
    # Every map tool reads only what the caller may. A member narrowed to Production never sees, counts or walks through
    # what runs in Development, and a service key reads nothing without a grant.
    class MapToolsReachTest < ActiveSupport::TestCase
      TOOLS = [ FindResources, GetResource, GetResourceLinks, GetResourceNeighbours, TraverseResourceMap, BlastRadius, ResourceMapStats ].freeze
      ON_WEB = {
        FindResources => {}, GetResource => { resource: "web" }, GetResourceLinks => { resource: "web" },
        GetResourceNeighbours => { resource: "web", include_suggestions: true },
        TraverseResourceMap => { resource: "web", direction: ResourceMap::Graph::DEPENDS_ON, hops: 6 },
        BlastRadius => { resource: "orders-db", include_suggestions: true }, ResourceMapStats => { group_by: ResourceMap::Stats::BY_ACCOUNT }
      }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @member = workspace_memberships(:bob_workspace_one)
        build_two_environment_map(@workspace)
      end

      test "every map tool authorizes as map read and only reads" do
        TOOLS.each do |tool|
          assert_equal [ Ability::Action::RESOURCE_MAP, Ability::Action::ACTION_READ ], tool.authorization(@workspace, {}), tool.name
          assert tool.annotations_value.read_only_hint, tool.name
        end
      end

      test "a member limited to Production never sees a name from Development or from a connection wired to no environment" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))

        ON_WEB.each do |tool, args|
          text = call(tool, @member, **args).to_json
          TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes text, name, "#{tool.name} named #{name}" }
        end
        assert_equal %w[orders-db web], call(FindResources, @member)[:resources].map { |row| row[:name] }
        assert_equal 2, call(ResourceMapStats, @member)[:resources]
        assert_equal "1 more link leads to resources in environments you cannot read", call(GetResource, @member, resource: "web")[:out_of_reach]
        assert_equal "1 more link leads to resources in environments you cannot read", call(GetResourceLinks, @member, resource: "web")[:out_of_reach]
      end

      test "the same member unlimited sees both environments, and the links between them" do
        assert_equal %w[dev-worker orders-db secret-db shop.example.com web], call(FindResources, @member)[:resources].map { |row| row[:name] }
        assert_includes call(GetResourceLinks, @member, resource: "web")[:links].map { |link| link[:sentence] }, "web uses dev-worker"
        assert_equal %w[dev-worker orders-db secret-db], call(TraverseResourceMap, @member, resource: "web", direction: ResourceMap::Graph::DEPENDS_ON, hops: 6)[:resources].map { |row| row[:name] }.sort
      end

      test "naming a resource outside the reader's environments reads exactly as naming nothing" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))
        hidden = map_resource(@workspace, "secret-db")

        (TOOLS - [ FindResources, ResourceMapStats ]).each do |tool|
          extra = tool == TraverseResourceMap ? { direction: ResourceMap::Graph::DEPENDENTS } : {}
          missing = call(tool, @member, resource: "nothing-here", **extra)[:error]
          assert_equal missing.sub("nothing-here", "secret-db"), call(tool, @member, resource: "secret-db", **extra)[:error], tool.name
          assert_equal missing.sub("nothing-here", hidden.id), call(tool, @member, resource: hidden.id, **extra)[:error], tool.name
        end
      end

      test "a service key is refused every map tool without a grant, and one limited to Development reads only Development" do
        key = api_keys(:read_only_key)
        TOOLS.each do |tool|
          refused = ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: key }, args: ON_WEB.fetch(tool))
          assert refused.error?, tool.name
          assert_match "lacks 'map:read' permission", refused.content.sole[:text]
        end

        limit_map_to(@workspace, key, catalog_entries(:development_env))
        allowed = ToolDispatcher.call(tool: FindResources, server_context: { workspace: @workspace, principal: key }, args: {})

        assert_equal %w[dev-worker secret-db], allowed.structured_content[:resources].map { |row| row[:name] }
      end

      test "a member whose only grant has lapsed reads nothing" do
        grant = limit_map_to(@workspace, @member, catalog_entries(:production_env))
        grant.update_column(:expires_at, 1.minute.ago)

        refused = ToolDispatcher.call(tool: FindResources, server_context: { workspace: @workspace, principal: @member }, args: {})

        assert refused.error?
      end

      private

      def call(tool, principal, **args) = tool.perform_with_principal(workspace: @workspace, principal: principal, args: args).structured_content
    end
  end
end
