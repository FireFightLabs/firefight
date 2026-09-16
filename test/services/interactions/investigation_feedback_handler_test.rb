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

  test "a thumbs up is recorded as that person's vote" do
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_CONFIRMED))

    verdict = @finding.verdicts.sole
    assert_equal Investigation::Finding::OUTCOME_CONFIRMED, verdict.outcome
    assert_equal @member, verdict.member
    assert_equal Investigation::Finding::OUTCOME_CONFIRMED, @finding.reload.outcome
  end

  test "anyone may change their mind, and the vote is replaced rather than doubled" do
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_CONFIRMED))
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_WRONG))

    assert_equal Investigation::Finding::OUTCOME_WRONG, @finding.verdicts.sole.outcome
    assert_equal Investigation::Finding::OUTCOME_WRONG, @finding.reload.outcome
  end

  test "a split room leaves the finding without an outcome" do
    Interactions::InvestigationFeedbackHandler.execute(interaction(Investigation::Finding::OUTCOME_CONFIRMED))
    Interactions::InvestigationFeedbackHandler.execute(
      interaction(Investigation::Finding::OUTCOME_WRONG, user_id: workspace_memberships(:bob_workspace_one).platform_user_id)
    )

    assert_equal 2, @finding.verdicts.count
    assert_nil @finding.reload.outcome
    assert_equal({ "confirmed" => 1, "wrong" => 1 }, @finding.tally)
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

  def interaction(outcome, finding_id: @finding.id, user_id: @member.platform_user_id)
    Interaction.new(
      type: Interaction::BLOCK_ACTIONS, platform: Platforms::SLACK, team_id: @workspace.platform_id,
      user_id: user_id, action_id: Identifiers::INVESTIGATION_FEEDBACK,
      action_value: "#{finding_id}:#{outcome}"
    )
  end
end
