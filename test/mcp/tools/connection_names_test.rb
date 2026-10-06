require "test_helper"

module Mcp
  module Tools
    # An action key names its connection by slug, which reads like the provider's name, so an outside agent reading the
    # log or the approvals is told the connection the way a person tells it apart, and its provider.
    class ConnectionNamesTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
        faylee.tools.create!(name: "api_request", params_schema: { "type" => "object" })
        @member = workspace_memberships(:alice_workspace_one)
      end

      test "search_activity names the connection and provider beside a tool's key, and none for a system action" do
        record!("faylee.api_request")
        record!("incidents.create")

        rows = SearchActivity.perform(workspace: @workspace, args: { limit: 50 }).structured_content[:activity]

        faylee = rows.find { |row| row[:ability] == "faylee.api_request" }
        assert_equal [ "Faylee (Northflank)", "northflank" ], faylee.values_at(:connection, :provider)
        assert_not rows.find { |row| row[:ability] == "incidents.create" }.key?(:connection)
      end

      test "search_approvals names the connection and provider beside a tool's key" do
        Ability::Approval.create!(workspace: @workspace, principal: @member, principal_label: "Alice", action_key: "faylee.api_request",
                                  request_digest: Ability::Approval.digest("faylee.api_request", {}, {}), required_role: WorkspaceMembership.roles[:admin])

        approval = SearchApprovals.perform(workspace: @workspace, args: {}).structured_content[:approvals].find { |row| row[:action_key] == "faylee.api_request" }

        assert_equal [ "Faylee (Northflank)", "northflank" ], approval.values_at(:connection, :provider)
      end

      private

      def record!(key)
        Ability::Invocation.create!(workspace: @workspace, principal: @member, principal_label: "Alice", action_key: key,
                                    decision: Ability::Invocation::DECISION_ALLOW, idempotency_key: SecureRandom.uuid)
      end
    end
  end
end
