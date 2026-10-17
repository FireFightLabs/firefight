require "test_helper"

class Ability::PrincipalNamedTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @agent = Agent.create!(workspace: @workspace, name: "Deploy bot", slug: "deploy_bot")
  end

  test "an approval names who asked the way a person reads it, for every kind of principal" do
    {
      SystemAgent.investigator => "Halon",
      SystemAgent.map_sweep => "Firefight map sweep",
      @agent => "Deploy bot",
      api_keys(:full_access_key) => api_keys(:full_access_key).name,
      workspace_memberships(:alice_workspace_one) => users(:alice).name
    }.each do |principal, name|
      assert_equal name, approval_by(principal).principal_name, principal.principal_label
    end
  end

  test "a ledger row names who acted the way a person reads it, for every kind of principal" do
    {
      SystemAgent.investigator => "Halon",
      @agent => "Deploy bot",
      api_keys(:full_access_key) => api_keys(:full_access_key).name,
      workspace_memberships(:alice_workspace_one) => users(:alice).name
    }.each do |principal, name|
      assert_equal name, invocation_by(principal).principal_name, principal.principal_label
    end
  end

  test "a row whose principal is gone still reads as the name it kept, never the machine label" do
    approval = approval_by(@agent)
    invocation = invocation_by(@agent)
    @agent.destroy!

    assert_equal "Deploy bot", approval.reload.principal_name
    assert_equal "Deploy bot", invocation.reload.principal_name
  end

  test "the investigator is Halon wherever a principal is named" do
    assert_equal "Halon", SystemAgent.investigator.actor_display_name
    assert_equal "system_agent:Halon", SystemAgent.investigator.principal_label
  end

  test "Slack's request card, its details and its DM name who asked in plain words" do
    approval = approval_by(SystemAgent.investigator)
    shown = ApprovalNotificationService.shown(approval)

    assert_equal "Halon wants to: delete catalogue", Slack::Messages::Approval.request_fallback(approval, shown: shown)
    assert_includes Slack::Modals::ApprovalDetails.build(approval, params: {}).to_json, "*Asked by*\\nHalon"
    assert_not_includes Slack::Messages::Approval.build_request(approval, shown: shown, rich: true).to_json, "system_agent"
  end

  test "MCP's approvals and activity name who asked and who acted in plain words, beside the machine label" do
    approval = approval_by(@agent)
    invocation = invocation_by(@agent)

    approvals = Mcp::Tools::SearchApprovals.perform(workspace: @workspace, args: {}).structured_content[:approvals]
    activity = Mcp::Tools::SearchActivity.perform(workspace: @workspace, args: { limit: 50 }).structured_content[:activity]

    assert_equal [ "agent:Deploy bot", "Deploy bot" ], approvals.find { |row| row[:id] == approval.id }.values_at(:principal, :principal_name)
    assert_equal [ "agent:Deploy bot", "Deploy bot" ], activity.find { |row| row[:id] == invocation.id }.values_at(:principal, :principal_name)
  end

  test "a call Halon made in a member's chat reads as Halon, for the member, wherever people and tools read it" do
    member = workspace_memberships(:alice_workspace_one)
    approval = approval_by(member, source: AbilityGateway::SOURCE_CONVERSATION)
    invocation = invocation_by(member, source: AbilityGateway::SOURCE_CONVERSATION)
    shown = "Halon, for #{users(:alice).name}"

    assert_equal [ shown, shown ], [ approval.principal_name, invocation.principal_name ]
    assert_equal shown, AbilityApprovalSerializer.one(approval)[:principalName]
    assert_equal shown, AbilityInvocationSerializer.one(invocation)[:principalName]
    approvals = Mcp::Tools::SearchApprovals.perform(workspace: @workspace, args: {}).structured_content[:approvals]
    activity = Mcp::Tools::SearchActivity.perform(workspace: @workspace, args: { limit: 50 }).structured_content[:activity]
    assert_equal shown, approvals.find { |row| row[:id] == approval.id }[:principal_name]
    assert_equal shown, activity.find { |row| row[:id] == invocation.id }[:principal_name]

    assert_equal users(:alice).name, Chat::HeldCall.new(approval: approval).asker_name, "who may run it is still the person"
    assert_equal "Halon", approval_by(SystemAgent.investigator, source: AbilityGateway::SOURCE_CONVERSATION).principal_name
  end

  test "a member asking Halon, such as answering it in a tracker's issue, reads as the member, not as Halon" do
    member = workspace_memberships(:alice_workspace_one)
    asked = Ability::Invocation.create!(
      workspace: @workspace, principal: member, principal_label: member.principal_label, action_key: Ability::Action::INVESTIGATIONS_CREATE,
      idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW, source: AbilityGateway::SOURCE_CONVERSATION
    )

    assert_equal users(:alice).name, asked.principal_name
  end

  test "a held call names whoever asked in plain words, a person or not" do
    assert_equal "Halon", Chat::HeldCall.new(approval: approval_by(SystemAgent.investigator)).asker_name
    assert_equal users(:alice).name, Chat::HeldCall.new(approval: approval_by(workspace_memberships(:alice_workspace_one))).asker_name
  end

  private

  def approval_by(principal, source: nil)
    Ability::Approval.create!(
      workspace: @workspace, principal: principal, principal_label: principal.principal_label, action_key: "catalog.delete", source: source,
      request_digest: Ability::Approval.digest("catalog.delete", {}, {}), required_role: WorkspaceMembership.roles[:admin]
    )
  end

  def invocation_by(principal, source: nil)
    Ability::Invocation.create!(
      workspace: @workspace, principal: principal, principal_label: principal.principal_label, action_key: "catalog.delete", source: source,
      idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW
    )
  end
end
