require "test_helper"

class Interactions::ApplyFixHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
  end

  test "the fix is applied as whoever clicked, from Slack" do
    alice = workspace_memberships(:alice_workspace_one)

    assert_enqueued_with(job: InvestigationFixJob, args: [ @plan.id ]) { Interactions::ApplyFixHandler.execute(press(alice)) }

    assert_equal [ Investigation::RemediationPlan::STATUS_APPLYING, alice, AbilityGateway::SOURCE_SLACK ], [ @plan.reload.status, @plan.approved_by, @plan.applied_from ]
  end

  test "someone who cannot run a step is told which one, only them, and nothing starts" do
    bob = workspace_memberships(:bob_workspace_one)
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:user] == bob.platform_user_id && arguments[:text].include?("Step 1 runs cloudflare_execute") }
                 .returns({ ok: true })

    assert_no_enqueued_jobs(only: InvestigationFixJob) { Interactions::ApplyFixHandler.execute(press(bob)) }
    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  test "a fix from another workspace is out of reach" do
    other = workspace_memberships(:alice_workspace_two)
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: workspaces(:slack_workspace_two).platform_id,
                                  user_id: other.platform_user_id, action_id: Identifiers::APPLY_FIX, action_value: @plan.id, channel_id: "C1")

    assert_nil Interactions::ApplyFixHandler.execute(interaction)
    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  private

  def press(member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: member.platform_user_id,
                    action_id: Identifiers::APPLY_FIX, action_value: @plan.id, channel_id: "C1")
  end
end
