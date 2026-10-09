require "test_helper"

module Mcp
  module Tools
    class SuggestResourceLinkTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
        ResourceMap.record!(integration.integration_environments.create!, ResourceMap::Snapshot.new(resources: [ found("web"), found("db") ]))
      end

      test "a suggestion goes on the map unconfirmed, with its evidence" do
        payload = call(from: "web", to: "db", relation: ResourceMap::RELATION_USES, evidence: "Its logs connect to db's host.")

        assert_equal "web uses db", payload[:suggested]
        link = ResourceMap::Link.find_by!(workspace: @workspace, origin: ResourceMap::ORIGIN_SUGGESTED)
        assert link.unconfirmed?
        assert_equal "Its logs connect to db's host.", link.note
      end

      test "either end can be named by its id on the map, and a name two share lists each one's map id and connection" do
        web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
        assert_equal "web uses db", call(from: web.id, to: "db", relation: ResourceMap::RELATION_USES, evidence: "x")[:suggested]

        other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
        ResourceMap.record!(other.integration_environments.create!,
                            ResourceMap::Snapshot.new(resources: [ ResourceMap::Found.new(provider: "northflank", account: "acme/faylee", kind: ResourceMap::KIND_SERVICE,
                                                                                          external_id: "web", name: "web") ]))
        faylee_web = ResourceMap::Resource.find_by!(workspace: @workspace, account: "acme/faylee")
        error = call(from: "web", to: "db", relation: ResourceMap::RELATION_PART_OF, evidence: "x")[:error]

        assert_match "map id #{faylee_web.id}, on Faylee (Northflank)", error
        assert_match "map id #{web.id}, on Northflank", error
        assert_match "Name it by its map id", error
      end

      test "a resource not on the map, or a pair already linked, is refused with the reason and marked failed" do
        assert_equal ResourceMap::Resource.not_found_words("checkout"), call(from: "checkout", to: "db", relation: ResourceMap::RELATION_USES, evidence: "x")[:error]

        call(from: "web", to: "db", relation: ResourceMap::RELATION_USES, evidence: "x")
        again = SuggestResourceLink.perform_with_principal(workspace: @workspace, principal: map_reader,
                                                           args: { from: "web", to: "db", relation: ResourceMap::RELATION_USES, evidence: "x" })
        assert again.error?
        assert_match "already on the map", again.structured_content[:error]
      end

      private

      def found(id) = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: id, name: id)

      def call(principal: map_reader, **args) = SuggestResourceLink.perform_with_principal(workspace: @workspace, principal: principal, args: args).structured_content
    end
  end
end
