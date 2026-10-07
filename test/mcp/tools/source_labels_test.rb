require "test_helper"

module Mcp
  module Tools
    # The activity log and the approvals name where a call came from the way a person reads it, never as the stored value.
    class SourceLabelsTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @member = workspace_memberships(:alice_workspace_one)
      end

      test "every source has a label, and a chat's calls read as Halon chat" do
        assert_equal AbilityGateway::SOURCES.sort, Ability::Source::LABELS.keys.sort
        assert_equal "Halon chat", Ability::Source.label(AbilityGateway::SOURCE_CONVERSATION)
        assert_nil Ability::Source.label(nil)
      end

      test "search_activity and the dashboard row carry the label beside the source" do
        invocation = Ability::Invocation.create!(
          workspace: @workspace, principal: @member, principal_label: "Alice", action_key: "incidents.create",
          decision: Ability::Invocation::DECISION_ALLOW, idempotency_key: SecureRandom.uuid, source: AbilityGateway::SOURCE_CONVERSATION
        )

        row = SearchActivity.perform(workspace: @workspace, args: { limit: 50 }).structured_content[:activity].find { |each| each[:id] == invocation.id }

        assert_equal [ AbilityGateway::SOURCE_CONVERSATION, "Halon chat" ], row.values_at(:source, :source_label)
        assert_equal "Halon chat", AbilityInvocationSerializer.one(invocation)[:sourceLabel]
      end

      test "search_approvals and the dashboard row carry the label beside the source" do
        approval = Ability::Approval.create!(
          workspace: @workspace, principal: @member, principal_label: "Alice", action_key: "incidents.create",
          request_digest: Ability::Approval.digest("incidents.create", {}, {}), required_role: WorkspaceMembership.roles[:admin],
          source: AbilityGateway::SOURCE_CONVERSATION
        )

        row = SearchApprovals.perform(workspace: @workspace, args: {}).structured_content[:approvals].find { |each| each[:id] == approval.id }

        assert_equal [ AbilityGateway::SOURCE_CONVERSATION, "Halon chat" ], row.values_at(:source, :source_label)
        assert_equal "Halon chat", AbilityApprovalSerializer.one(approval)[:sourceLabel]
      end
    end
  end
end
