require "test_helper"

class Interactions::MarkFixStepDoneHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "a person's step is marked done by whoever clicked, and the fix carries on" do
    step = @plan.steps.third

    assert_enqueued_with(job: InvestigationFixJob, args: [ @plan.id ]) { Interactions::MarkFixStepDoneHandler.execute(press(step)) }

    assert_equal [ Investigation::RemediationStep::STATUS_DONE, @bob ], [ step.reload.status, step.done_by ]
  end

  test "a step Firefight runs cannot be marked done, and only the clicker is told why" do
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text] == "Firefight runs step 1 itself once the fix is applied." }.returns({ ok: true })

    assert_no_enqueued_jobs(only: InvestigationFixJob) { Interactions::MarkFixStepDoneHandler.execute(press(@plan.steps.first)) }
  end

  private

  def press(step)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
                    action_id: Identifiers::MARK_FIX_STEP_DONE, action_value: step.id, channel_id: "C1")
  end
end
