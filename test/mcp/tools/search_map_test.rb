require "test_helper"

module Mcp
  module Tools
    class SearchMapTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        @member = workspace_memberships(:bob_workspace_one)
        build_two_environment_map(@workspace)
        ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: map_resource(@workspace, "web"))
        SearchDocument.index!(ResourceMap::Resource, ResourceMap::Resource.where(workspace: @workspace).pluck(:id))
        SearchDocument.index!(CatalogEntry, @workspace.catalog_entries.pluck(:id))
      end

      test "it authorizes as map read, only reads and sits in the map's tool group" do
        assert_equal [ Ability::Action::RESOURCE_MAP, Ability::Action::ACTION_READ ], SearchMap.authorization(@workspace, {})
        assert SearchMap.annotations_value.read_only_hint
        group = Chat::Tools::Groups::FIREFIGHT.find { |each| each.tools.include?(SEARCH_MAP) }
        assert_equal Chat::Tools::Groups::MAP, group.key
      end

      test "each result says what it is, why it matched and where it opens" do
        Chat::Memory.create!(workspace: @workspace, subject: catalog_entries(:auth_service), text: "Auth Service keeps sessions in orders-db",
                             state: Chat::Memory::STATE_CONFIRMED, confirmed_by: @admin)

        results = call(@admin, query: "orders-db")[:results]

        resource = results.first
        assert_equal({ type: "resource", title: "orders-db", why: "Exactly its name.", kind: ResourceMap::KIND_DATABASE, provider: "northflank",
                       account: "acme/shop", environment: "Production", status: "running" }, resource.except(:id, :link))
        assert_equal "/app/map?resource=#{resource[:id]}&view=focus", resource[:link]
        memory = results.find { |result| result[:type] == SearchDocument::Search::TYPE_MEMORY }
        assert_equal "Auth Service", memory[:about]
        assert_match "confirmed by", memory[:trust]
        auth = call(@admin, query: "auth service")[:results].find { |result| result[:type] == SearchDocument::Search::TYPE_CATALOG_ENTRY }
        assert_equal({ catalog_type: "Service", slug: "auth_service", description: "Handles authentication." }, auth.slice(:catalog_type, :slug, :description))
      end

      test "the find_resources filters narrow it, and one the catalog does not hold is refused" do
        assert_equal [ "orders-db" ], call(@admin, query: "db", environment: [ "production" ])[:results].map { |result| result[:title] }
        assert_equal [ "web" ], call(@admin, query: "web", owner: "Platform Team")[:results].map { |result| result[:title] }
        assert_equal "No team called Nobody is in the catalog.", text(response(@admin, query: "web", owner: "Nobody"))
      end

      test "a member narrowed to Production is never told a name from Development" do
        limit_map_to(@workspace, @member, catalog_entries(:production_env))

        payload = call(@member, query: "secret-db dev-worker shop.example.com").to_json

        TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes payload, name }
      end

      test "a service key reads only the types it was granted, and says which it could not search" do
        key = api_keys(:read_only_key)
        refused = ToolDispatcher.call(tool: SearchMap, server_context: { workspace: @workspace, principal: key }, args: { query: "web" })
        assert refused.error?
        assert_match "lacks 'map:read' permission", refused.content.sole[:text]

        limit_map_to(@workspace, key, catalog_entries(:production_env))
        allowed = ToolDispatcher.call(tool: SearchMap, server_context: { workspace: @workspace, principal: key }, args: { query: "auth" })

        assert_equal [ "web" ], allowed.structured_content[:results].map { |result| result[:title] }
        assert_equal [ "catalog_entry: not readable with this connection's permissions", "memory: not readable with this connection's permissions" ],
                     allowed.structured_content[:not_searched]
      end

      test "a blank query and a cursor from another search are refused with a sentence" do
        assert_equal "Say what to find first.", text(response(@admin, query: " "))
        cursor = call(@admin, query: "e", limit: 1)[:next_cursor]
        assert_match "another search", text(response(@admin, query: "web", cursor: cursor))
      end

      private

      def response(principal, **args) = SearchMap.perform_with_principal(workspace: @workspace, principal: principal, args: args)

      test "an approval rule never holds it, or any other map read, since reads never wait" do
        @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })

        searched = ToolDispatcher.call(tool: SearchMap, server_context: { workspace: @workspace, principal: @member }, args: { query: "web" })
        assert_not searched.error?
        assert_not @workspace.ability_approvals.exists?(action_key: Ability::Action::MAP_READ)

        read = ToolDispatcher.call(tool: GetResourceMap, server_context: { workspace: @workspace, principal: @member }, args: {})
        assert_not read.error?
        assert_empty @workspace.ability_approvals
      end

      def call(principal, **args) = response(principal, **args).structured_content

      def text(response) = response.content.sole[:text]
    end
  end
end
