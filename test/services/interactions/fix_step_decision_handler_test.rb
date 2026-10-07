require "test_helper"

class Interactions::FixStepDecisionHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @plan = build_fix_plan(@workspace)
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    approval = @workspace.ability_approvals.create!(
      principal: @alice, principal_label: "user:Alice Smith", action_key: "cloudflare.execute", request_digest: "d", required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: @alice, held_for_run: true, run_expires_at: 1.hour.from_now
    )
    @step = @plan.steps.first
    @step.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, approval_id: approval.id, state_change: Chat::CurrentState::UNCHANGED,
                         state_checked_at: Time.current)
  end

  test "Run on the thread claims the step once and hands it to the fix's job with its approval" do
    assert_enqueued_with(job: InvestigationFixJob, args: [ @plan.id, @step.id, @step.approval_id ]) do
      Interactions::FixStepDecisionHandler.execute(press(Identifiers::FIX_STEP_RUN))
    end
    assert_equal Investigation::RemediationStep::STATUS_RUNNING, @step.reload.status

    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text] == "Step 1 is running." }.returns({ ok: true })
    assert_no_enqueued_jobs(only: InvestigationFixJob) { Interactions::FixStepDecisionHandler.execute(press(Identifiers::FIX_STEP_RUN)) }
  end

  test "Dismiss on the thread skips the step" do
    Interactions::FixStepDecisionHandler.execute(press(Identifiers::FIX_STEP_DISMISS))

    assert_equal Investigation::RemediationStep::STATUS_SKIPPED, @step.reload.status
  end

  private

  def press(action_id)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @alice.platform_user_id,
                    action_id: action_id, action_value: @step.id, channel_id: "C1")
  end
end
