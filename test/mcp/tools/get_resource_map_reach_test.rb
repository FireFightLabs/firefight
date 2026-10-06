require "test_helper"

module Mcp
  module Tools
    class GetResourceMapReachTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @member = workspace_memberships(:bob_workspace_one)
        build_two_environment_map(@workspace)
      end

      test "a member reads every environment's resources and connections by default" do
        payload = call(@member)

        assert_equal %w[dev-worker orders-db secret-db shop.example.com web], names(payload)
        assert_equal 3, payload[:connections].size
      end

      test "a member limited to Production reads only what runs there, and never a name from outside it" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))

        payload = call(@member)

        assert_equal %w[orders-db web], names(payload)
        assert_equal [ [ "Jobs could not be read in Production" ] ], payload[:connections].map { |connection| connection[:gaps] }
        assert_no_hidden_name(payload)
      end

      test "a fact sheet leaves out a link to a resource outside the reader's environments, counts it, and never names it" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))

        sheet = call(@member, resource: "web")[:resources].sole

        assert_equal [ "web uses orders-db (declared by Northflank)" ], sheet[:links]
        assert_equal "1 more link within two hops leads to resources in environments you cannot read", sheet[:out_of_reach]
        assert_no_hidden_name(sheet)
      end

      test "a setting of a service outside the reader's environments that points at a store they read is never named" do
        ResourceMap::Link.create!(workspace: @workspace, from_resource: map_resource(@workspace, "dev-worker"), to_resource: map_resource(@workspace, "orders-db"),
                                  relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_MATCHED, variables: [ "SECRET_DB_URL" ],
                                  clues: [ "SECRET_DB_URL on dev-worker names the address" ], last_seen_at: Time.current)
        limit_map_to(@workspace, @member, catalog_entries(:production_env))

        sheet = GetResourceMap.perform_with_principal(workspace: @workspace, principal: @member, args: { resource: "orders-db" }).structured_content
        links = GetResourceLinks.perform_with_principal(workspace: @workspace, principal: @member, args: { resource: "orders-db" }).structured_content
        view = ResourceMap::View.new(@workspace, @member).links

        [ sheet, links, view.map(&:variables) ].each { |read| assert_not_includes read.to_json, "SECRET_DB_URL" }
        assert_no_hidden_name(sheet)
      end

      test "naming a resource outside the reader's environments reads the same as naming nothing" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))

        assert_equal call(@member, resource: "nothing-here")[:error].sub("nothing-here", "secret-db"), call(@member, resource: "secret-db")[:error]
      end

      test "an admin and the investigator read the whole map, and a sheet of web names everything near it" do
        assert_equal 5, names(call(workspace_memberships(:alice_workspace_one))).size
        sheet = call(SystemAgent.investigator, resource: "web")[:resources].sole

        assert_includes sheet[:links], "web uses dev-worker (added by a person)"
        assert_nil sheet[:out_of_reach]
      end

      test "a service key needs a grant, and one limited to Development reads only Development" do
        key = api_keys(:read_only_key)
        refused = ToolDispatcher.call(tool: GetResourceMap, server_context: { workspace: @workspace, principal: key }, args: {})
        assert refused.error?
        assert_match "lacks 'map:read' permission", refused.content.sole[:text]

        limit_map_to(@workspace, key, catalog_entries(:development_env))
        allowed = ToolDispatcher.call(tool: GetResourceMap, server_context: { workspace: @workspace, principal: key }, args: {})

        assert_equal %w[dev-worker secret-db], names(allowed.structured_content)
      end

      test "suggesting a link to a resource outside the caller's environments answers as for one not on the map, and writes nothing" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))
        suggest = ->(to) { SuggestResourceLink.perform_with_principal(workspace: @workspace, principal: @member,
                                                                      args: { from: "web", to: to, relation: ResourceMap::RELATION_USES, evidence: "logs" }).structured_content }

        assert_equal suggest.call("nothing-here")[:error].sub("nothing-here", "secret-db"), suggest.call("secret-db")[:error]
        assert_not ResourceMap::Link.exists?(to_resource: map_resource(@workspace, "secret-db"), origin: ResourceMap::ORIGIN_SUGGESTED)
      end

      private

      def call(principal, **args) = GetResourceMap.perform_with_principal(workspace: @workspace, principal: principal, args: args).structured_content

      def names(payload) = payload[:accounts].flat_map { |account| account[:resources].map { |line| line.split(", ")[1] } }.sort

      def assert_no_hidden_name(payload)
        text = payload.to_json
        TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes text, name }
      end
    end
  end
end
