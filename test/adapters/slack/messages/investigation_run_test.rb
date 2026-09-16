require "test_helper"

class Slack::Messages::InvestigationRunTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    investigation = @incident.workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @finding = investigation.conclude!(
      summary: "The **14:02 deploy** raised the pool size", evidence: [ "commit abc123" ], gaps: "production logs"
    )
  end

  test "the opening message names the incident and who asked" do
    text = Slack::Messages::InvestigationRun.started(incident: @incident, started_by: "Alice").sole.dig(:text, :text)

    assert_match @incident.identifier, text
    assert_match "Started by Alice", text
  end

  test "an answer carries the evidence, the gaps and Slack's own feedback buttons" do
    blocks = Slack::Messages::InvestigationRun.finding(finding: @finding)

    assert_equal "*14:02 deploy* raised the pool size", blocks.first.dig(:text, :text).split("The ").last
    assert_match "commit abc123", blocks.second.dig(:text, :text)
    assert_match "production logs", blocks.third[:elements].sole[:text]

    feedback = blocks.last[:elements].sole
    assert_equal "context_actions", blocks.last[:type]
    assert_equal "feedback_buttons", feedback[:type]
    assert_equal Identifiers::INVESTIGATION_FEEDBACK, feedback[:action_id]
    assert_equal "#{@finding.id}:#{Investigation::Finding::OUTCOME_CONFIRMED}", feedback[:positive_button][:value]
    assert_equal "#{@finding.id}:#{Investigation::Finding::OUTCOME_WRONG}", feedback[:negative_button][:value]
  end

  test "an answer with nothing to cite leaves the evidence out rather than showing an empty list" do
    finding = @finding.investigation.finding
    finding.update!(evidence: [], gaps: nil)

    blocks = Slack::Messages::InvestigationRun.finding(finding: finding)

    assert_equal 2, blocks.size
    assert_equal "context_actions", blocks.last[:type]
  end
end
