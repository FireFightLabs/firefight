require "test_helper"

class Slack::Messages::InvestigationRunTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    investigation = @incident.workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    investigation.steps.create!(
      position: 1, tool_name: "commit_lookup", label: "Commit lookup abc123", action_key: "github.commit_lookup",
      status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current
    )
    @finding = investigation.conclude!(
      summary: "The **14:02 deploy** raised the pool size",
      evidence: [ { claim: "The commit raised the pool size", steps: [ 1 ] } ], gaps: "production logs"
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
    assert_match "• The commit raised the pool size _(Commit lookup abc123)_", blocks.second.dig(:text, :text)
    assert_match "production logs", blocks.third[:elements].sole[:text]

    feedback = blocks.last[:elements].sole
    assert_equal "context_actions", blocks.last[:type]
    assert_equal "feedback_buttons", feedback[:type]
    assert_equal Identifiers::INVESTIGATION_FEEDBACK, feedback[:action_id]
    assert_equal "#{@finding.id}:#{Investigation::Finding::OUTCOME_CONFIRMED}", feedback[:positive_button][:value]
    assert_equal "#{@finding.id}:#{Investigation::Finding::OUTCOME_WRONG}", feedback[:negative_button][:value]
  end

  test "a run that stopped on our side offers one button to run it again" do
    blocks = Slack::Messages::InvestigationRun.stopped(reason: "Something went wrong on my side", rerun: @incident)

    button = blocks.last[:elements].sole
    assert_equal "actions", blocks.last[:type]
    assert_equal Identifiers::START_INVESTIGATION, button[:action_id]
    assert_equal @incident.id, button[:value]
  end

  test "a run that stopped for its own reasons offers no button, since running it again would end the same way" do
    blocks = Slack::Messages::InvestigationRun.stopped(reason: "Budget spent before it could answer")

    assert_equal [ "section" ], blocks.map { |block| block[:type] }
  end

  test "an answer with nothing to cite leaves the evidence out rather than showing an empty list" do
    finding = @finding.investigation.finding
    finding.evidence_items.destroy_all
    finding.update!(gaps: nil)

    blocks = Slack::Messages::InvestigationRun.finding(finding: finding)

    assert_equal 2, blocks.size
    assert_equal "context_actions", blocks.last[:type]
  end
end
