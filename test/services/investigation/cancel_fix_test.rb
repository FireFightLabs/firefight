require "test_helper"

class Investigation::CancelFixTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_WEB)
    WorkspaceAdapter.stubs(:for).returns(stub_everything(post_fix_progress: { message_id: "1.2", channel_id: "C1" }))
  end

  test "cancelling stops what has not run, withdraws its approval, lets a running step finish, and leaves it undoable" do
    first, second, third = @plan.steps.to_a
    first.move!(from: "proposed", to: "running", started_at: Time.current)
    approval = @workspace.ability_approvals.create!(principal_type: "WorkspaceMembership", principal_id: @alice.id, principal_label: "Alice",
                                                    action_key: "cloudflare.execute", request_digest: "x", scope: {}, params: {}, required_role: "admin")
    second.update_columns(status: Investigation::RemediationStep::STATUS_WAITING_APPROVAL, approval_id: approval.id)
    ApprovalNotificationService.expects(:mark_resolved!).with(approval)

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { assert_nil Investigation::FixRunner.cancel!(@plan, by: @bob) }

    assert_equal [ Investigation::RemediationPlan::STATUS_CANCELLED, @bob ], [ @plan.reload.status, @plan.cancelled_by ]
    assert_equal [ "running", "skipped", "skipped" ], [ first.reload.status, second.reload.status, third.reload.status ]
    assert_equal "Cancelled by Bob Jones before it ran.", third.result
    assert approval.reload.status == Ability::Approval::STATUS_EXPIRED
    assert @plan.moving?, "the running step is still watched until it finishes"

    first.finish!(Investigation::RemediationStep::STATUS_DONE, result: "Rule deleted")
    @plan.settle!
    assert_equal Investigation::RemediationPlan::STATUS_CANCELLED, @plan.reload.status, "a finished step never reopens a cancelled fix"
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
    assert_nil @plan.undo_blocked_reason
  end

  test "only a fix being applied is cancelled, once" do
    assert_nil Investigation::FixRunner.cancel!(@plan, by: @bob)
    assert_equal "Only a fix being applied can be cancelled.", Investigation::FixRunner.cancel!(@plan.reload, by: @alice)
    assert_equal @bob, @plan.reload.cancelled_by
  end

  test "a step is never started once its fix is cancelled, even by a worker that already chose it" do
    third = @plan.steps.third
    @plan.cancel!(by: @bob)

    assert_not third.claim!(from: Investigation::RemediationStep::STATUS_PROPOSED)
    assert_equal "proposed", third.reload.status
  end

  test "a step asking for approval as the fix is cancelled is stopped, and nobody is left asked" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    first = @plan.steps.first
    first.claim!(from: Investigation::RemediationStep::STATUS_PROPOSED)
    runner = Investigation::FixRunner.new(@plan)
    AbilityGateway.stubs(:approval_gate!).with { @plan.cancel!(by: @bob) || true }.raises(AbilityGateway::PendingApproval.new(@workspace.ability_approvals.create!(
      principal_type: "WorkspaceMembership", principal_id: @alice.id, principal_label: "Alice", action_key: "cloudflare.execute", request_digest: "x",
      scope: {}, params: {}, required_role: "admin"
    )))
    ApprovalNotificationService.stubs(:mark_resolved!)

    runner.send(:call, first)

    assert_equal "skipped", first.reload.status
    assert_equal Ability::Approval::STATUS_EXPIRED, first.approval.status
  end

  test "a fix with a step still running offers no undo yet" do
    @plan.steps.first.claim!(from: Investigation::RemediationStep::STATUS_PROPOSED)
    @plan.steps.second.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    @plan.cancel!(by: @bob)

    assert_match "still running", @plan.reload.undo_blocked_reason
  end

  test "a withdrawn approval says so, and expiring one never overwrites an approval given at the same moment" do
    approval = @workspace.ability_approvals.create!(principal_type: "WorkspaceMembership", principal_id: @alice.id, principal_label: "Alice",
                                                    action_key: "cloudflare.execute", request_digest: "x", scope: {}, params: {}, required_role: "admin")
    stale = Ability::Approval.find(approval.id)
    approval.update_columns(status: Ability::Approval::STATUS_APPROVED)

    stale.expire!
    assert_equal Ability::Approval::STATUS_APPROVED, stale.status

    approval.update_columns(status: Ability::Approval::STATUS_PENDING)
    approval.expire!
    assert_includes Slack::Messages::Approval.build_resolved(approval).last.dig(:text, :text), "*Withdrawn*"
  end
end
