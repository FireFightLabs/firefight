require "test_helper"

class Investigation::RemediationPlanMovingTest < ActiveSupport::TestCase
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_WEB)
  end

  test "an approved step Halon is still checking keeps the run page current" do
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, state_checked_at: nil)

    assert @plan.reload.moving?
  end

  test "an approved step already checked waits on a person, so the page stops polling" do
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, state_checked_at: Time.current)
    @plan.steps.where.not(id: @plan.steps.first.id).update_all(status: Investigation::RemediationStep::STATUS_SKIPPED)

    assert_not @plan.reload.moving?
  end

  test "a step waiting for approval keeps the run page current, since the approval can come from elsewhere" do
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_WAITING_APPROVAL)
    @plan.steps.where.not(id: @plan.steps.first.id).update_all(status: Investigation::RemediationStep::STATUS_SKIPPED)

    assert @plan.reload.moving?
  end

  test "an approved step that lapsed says so, worded from the approval's run window" do
    step = @plan.steps.first
    assert_nil step.lapsed_reason

    step.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED)
    assert_equal "An approver approved it, but nobody ran it within 1 hour, so the approval expired.", step.reload.lapsed_reason
  end
end
