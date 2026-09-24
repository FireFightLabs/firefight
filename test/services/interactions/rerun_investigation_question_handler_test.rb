require "test_helper"

class Interactions::RerunInvestigationQuestionHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @original = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_FAILED, channel_id: "C0GENERAL",
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
  end

  test "the question is asked again in the same place, as whoever pressed it" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)

    assert_enqueued_with(job: InvestigationJob) { Interactions::RerunInvestigationQuestionHandler.execute(press) }

    rerun = @workspace.investigations.where.not(id: @original.id).sole
    assert_equal [ "checkout is slow", "C0GENERAL", @bob ], [ rerun.question, rerun.channel_id, rerun.triggered_by ]
  end

  test "with AI SRE turned off since, it says so and starts nothing" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text].include?("not turned on") }.returns({ ok: true })

    assert_no_enqueued_jobs(only: InvestigationJob) { Interactions::RerunInvestigationQuestionHandler.execute(press) }
  end

  private

  def press
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @bob.platform_user_id,
      action_id: Identifiers::RERUN_INVESTIGATION_QUESTION, action_value: @original.id, channel_id: "C0GENERAL"
    )
  end
end
