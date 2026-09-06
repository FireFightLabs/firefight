require "test_helper"

class Slack::Messages::FirstIncidentWalkthroughTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @incident.workspace.update!(incidents_channel_id: "C_INCIDENTS")
  end

  test "every step is a titled message with a divider and one instruction" do
    (1..WorkspaceOnboarding::WALKTHROUGH_DONE).each do |step|
      blocks = Slack::Messages::FirstIncidentWalkthrough.build(@incident, step: step)

      assert_equal "section", blocks.first[:type], "step #{step}"
      assert_equal "divider", blocks.second[:type], "step #{step}"
      assert blocks.third.dig(:text, :text).present?, "step #{step}"
      assert Slack::Messages::FirstIncidentWalkthrough.fallback_text(step).present?
    end
  end

  test "the steps that ask for a click carry the button, and none says above" do
    messages = (1..5).to_h { |step| [ step, Slack::Messages::FirstIncidentWalkthrough.build(@incident, step: step) ] }
    bodies = messages.transform_values { |blocks| blocks.third.dig(:text, :text) }
    buttons = messages.transform_values { |blocks| blocks.find { |block| block[:type] == "actions" }&.dig(:elements, 0) }

    assert_equal Identifiers::SET_INCIDENT_LEAD_SELF, buttons[1][:action_id]
    assert_equal @incident.id, buttons[1][:value]
    assert_match "<#C_INCIDENTS>", bodies[1]
    assert_nil buttons[2]
    Slack::Messages::FirstIncidentWalkthrough::SCRIPT.each { |line| assert_match line, bodies[2] }
    assert_equal Identifiers::RESOLVE_INCIDENT, buttons[3][:action_id]
    assert_equal Identifiers::WRITE_POSTMORTEM, buttons[4][:action_id]
    assert_nil buttons[5]
    assert_match "share <#C_INCIDENTS>", bodies[5]
    assert_no_match(/above|write-up/i, bodies.values.join)
  end

  test "names the channel plainly when the workspace has none stored" do
    @incident.workspace.update!(incidents_channel_id: nil)

    assert_match "#incidents", Slack::Messages::FirstIncidentWalkthrough.build(@incident, step: 1).third.dig(:text, :text)
  end
end
