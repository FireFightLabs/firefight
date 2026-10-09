require "test_helper"

class Mcp::ToolDispatcherTest < ActiveSupport::TestCase
  include IssueTrackerTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "one of Firefight's own tools answering with an error is ledgered as an error with what it said" do
    Mcp::Tools::CompleteActionItem.stubs(:perform_with_principal).returns(Mcp::ToolDispatcher.error_response("This action item is already done."))

    response = Mcp::ToolDispatcher.call(tool: Mcp::Tools::CompleteActionItem, server_context: { workspace: @workspace, principal: @alice },
                                        args: { incident: "INC-1", action_item: "1" })

    assert response.error?
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "incidents.update", principal: @alice)
    assert_equal [ AbilityGateway::SOURCE_MCP, Ability::Invocation::OUTCOME_ERROR, "This action item is already done." ],
                 [ invocation.source, invocation.outcome, invocation.error_summary ]
  end

  test "a write-only secret is ledgered and held for approval as a digest, never shown, and the approved retry still matches" do
    linear = connect_tracker!(@workspace, provider: "linear")
    approver = workspace_memberships(:bob_workspace_one)
    approver.update!(role: :admin)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(priority: 1, conditions: PolicyRule::ApprovalConditions.build(action_keys: [ "workspace.update" ]),
                                outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } })
    secret = "whsec-kept-out-of-the-ledger"
    args = { issue_tracker: linear.slug, issue_webhook_secret: secret }
    context = { workspace: @workspace, principal: @alice }

    assert Mcp::ToolDispatcher.call(tool: Mcp::Tools::UpdateWorkspaceSettings, server_context: context, args: args).error?
    approval = @workspace.ability_approvals.find_by!(action_key: "workspace.update")
    listed = Mcp::Tools::SearchApprovals.perform(workspace: @workspace, args: {})
    assert_not_includes listed.structured_content.to_json, secret

    approval.approve!(by: approver)
    response = Mcp::ToolDispatcher.call(tool: Mcp::Tools::UpdateWorkspaceSettings, server_context: context, args: args.merge(approval_id: approval.id))

    assert_not response.error?
    assert_equal secret, linear.integration_environments.sole.issue_webhook_secret
    stored = Ability::Invocation.where(workspace: @workspace).pluck(:params) + Ability::Approval.where(workspace: @workspace).pluck(:params)
    assert stored.any?
    assert stored.none? { |params| params.to_json.include?(secret) }
  end
end
