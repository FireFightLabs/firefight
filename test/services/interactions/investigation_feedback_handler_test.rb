require "test_helper"

class Interactions::InvestigationFeedbackHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @finding = @investigation.conclude!(summary: "The 14:02 deploy did it")
  end

  test "a thumbs up records that the answer was right, and who said so" do
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_CONFIRMED))

    @finding.reload
    assert_equal Investigation::Finding::OUTCOME_CONFIRMED, @finding.outcome
    assert_equal @member, @finding.outcome_by
    assert_not_nil @finding.outcome_at
  end

  test "the first vote stands" do
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_CONFIRMED))
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_WRONG))

    assert_equal Investigation::Finding::OUTCOME_CONFIRMED, @finding.reload.outcome
  end

  test "a finding from another workspace is not reachable" do
    other = workspaces(:slack_workspace_two).investigations.create!(
      subject: incidents(:active_p0_ws2), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    finding = other.conclude!(summary: "Something else")

    Interactions::InvestigationFeedbackHandler.execute(
      interaction(Investigation::Finding::OUTCOME_WRONG, finding_id: finding.id)
    )

    assert_nil finding.reload.outcome
  end

  private

  def interaction(outcome, finding_id: @finding.id)
    Interaction.new(
      type: Interaction::BLOCK_ACTIONS, platform: Platforms::SLACK, team_id: @workspace.platform_id,
      user_id: @member.platform_user_id, action_id: Identifiers::INVESTIGATION_FEEDBACK,
      action_value: "#{finding_id}:#{outcome}"
    )
  end
end
