require "test_helper"

class ApprovalResumptionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :ability_actions

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @approver = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)

    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ Ability::Action::RISK_WRITE ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )

    Slack::WorkspaceAdapter.any_instance.stubs(:post_ephemeral)
  end

  test "a parked interaction stores what it needs to be replayed" do
    Interactions::MarkActionDoneHandler.expects(:execute).never

    assert_difference "Ability::Approval.count", 1 do
      InteractionDispatcher.dispatch(interaction)
    end

    approval = @workspace.ability_approvals.order(:created_at).last
    assert_equal ApprovalResumption::KIND_INTERACTION, approval.resume_payload["kind"]
    assert_equal "C12345678", approval.resume_payload["channel_id"]
    assert_equal @member.platform_user_id, approval.resume_payload["user_id"]
  end

  test "approving replays the request and consumes the approval" do
    InteractionDispatcher.dispatch(interaction)
    approval = @workspace.ability_approvals.order(:created_at).last

    Interactions::MarkActionDoneHandler.expects(:execute).once
    approval.approve!(by: @approver)
    ApprovalResumption.resume!(approval)

    assert approval.reload.consumed_at.present?
  end

  test "a decision enqueues the replay" do
    InteractionDispatcher.dispatch(interaction)
    approval = @workspace.ability_approvals.order(:created_at).last

    assert_enqueued_with(job: AbilityApprovalResumptionJob) do
      approval.approve!(by: @approver)
    end
  end

  test "an approval with nothing parked is left alone" do
    approval = @workspace.ability_approvals.create!(
      principal_type: "WorkspaceMembership", principal_id: @member.id,
      principal_label: @member.principal_label, action_key: "incidents.update",
      request_digest: SecureRandom.hex, required_role: WorkspaceMembership.roles[:admin]
    )

    assert_no_enqueued_jobs(only: AbilityApprovalResumptionJob) do
      approval.approve!(by: @approver)
    end
  end

  test "a replay that already ran does not park a fresh request" do
    InteractionDispatcher.dispatch(interaction)
    approval = @workspace.ability_approvals.order(:created_at).last
    approval.approve!(by: @approver)
    Interactions::MarkActionDoneHandler.stubs(:execute)
    ApprovalResumption.resume!(approval)

    assert_no_difference "Ability::Approval.count" do
      ApprovalResumption.resume!(approval.reload)
    end
  end

  test "an expiring approval replays nothing" do
    InteractionDispatcher.dispatch(interaction)
    approval = @workspace.ability_approvals.order(:created_at).last

    assert_no_enqueued_jobs(only: AbilityApprovalResumptionJob) do
      approval.expire!
    end
  end

  test "a denied request tells the person who asked" do
    InteractionDispatcher.dispatch(interaction)
    approval = @workspace.ability_approvals.order(:created_at).last
    approval.deny!(by: @approver)

    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).once
    ApprovalResumption.decline!(approval)
  end

  private

  def interaction
    @interaction ||= Interaction.new(
      type: Interaction::BLOCK_ACTIONS,
      action_id: Identifiers::MARK_ACTION_DONE,
      platform: Platforms::SLACK,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      channel_id: "C12345678",
      action_value: @incident.id
    )
  end
end
