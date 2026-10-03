require "test_helper"

class Interactions::CancelFixHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "cancelling from Slack stops the fix as whoever clicked, and tells only them" do
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:user] == @bob.platform_user_id && arguments[:text] == Investigation::FixRunner::CANCELLED }
                 .returns({ ok: true })

    Interactions::CancelFixHandler.execute(press)

    assert_equal [ Investigation::RemediationPlan::STATUS_CANCELLED, @bob ], [ @plan.reload.status, @plan.cancelled_by ]
  end

  test "a fix not being applied is left alone, and the clicker is told why" do
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text] == "Only a fix being applied can be cancelled." }.returns({ ok: true })

    Interactions::CancelFixHandler.execute(press)

    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  private

  def press
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
                    action_id: Identifiers::CANCEL_FIX, action_value: @plan.id, channel_id: "C1")
  end
end
