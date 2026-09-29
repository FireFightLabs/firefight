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

      test "a resource not on the map, or a pair already linked, is refused with the reason" do
        assert_match "get_resource_map shows what is", call(from: "checkout", to: "db", relation: ResourceMap::RELATION_USES, evidence: "x")[:error]

        call(from: "web", to: "db", relation: ResourceMap::RELATION_USES, evidence: "x")
        assert_match "already on the map", call(from: "web", to: "db", relation: ResourceMap::RELATION_USES, evidence: "x")[:error]
      end

      private

      def found(id) = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: id, name: id)

      def call(**args) = SuggestResourceLink.perform(workspace: @workspace, args: args).structured_content
    end
  end
end
