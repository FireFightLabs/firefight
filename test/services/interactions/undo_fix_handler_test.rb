require "test_helper"

class Interactions::UndoFixHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @bob = workspace_memberships(:bob_workspace_one)
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
  end

  test "asking from Slack starts writing the undo of an applied fix and tells only the clicker" do
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_APPLIED)
    @plan.steps.update_all(status: Investigation::RemediationStep::STATUS_DONE)
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:user] == @bob.platform_user_id && arguments[:text] == Investigation::UndoWriter::WRITING }
                 .returns({ ok: true })

    assert_enqueued_with(job: InvestigationUndoJob, args: [ @plan.id ]) { Interactions::UndoFixHandler.execute(press) }
    assert_equal @bob, @plan.reload.undo_requested_by
  end

  test "a fix that was never applied is not undone, and only the clicker is told why" do
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text] == "Only a fix that was applied can be undone." }.returns({ ok: true })

    assert_no_enqueued_jobs(only: InvestigationUndoJob) { Interactions::UndoFixHandler.execute(press) }
  end

  private

  def press
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
                    action_id: Identifiers::UNDO_FIX, action_value: @plan.id, channel_id: "C1")
  end
end
