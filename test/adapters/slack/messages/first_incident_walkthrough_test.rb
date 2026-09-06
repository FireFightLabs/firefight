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

  test "the steps point at the buttons and the channel in order" do
    bodies = (1..5).map { |step| Slack::Messages::FirstIncidentWalkthrough.build(@incident, step: step).third.dig(:text, :text) }

    assert_match "Make me Lead", bodies[0]
    assert_match "<#C_INCIDENTS>", bodies[0]
    Slack::Messages::FirstIncidentWalkthrough::SCRIPT.each { |line| assert_match line, bodies[1] }
    assert_match "Resolve", bodies[2]
    assert_match "Write the postmortem", bodies[3]
    assert_match "share <#C_INCIDENTS>", bodies[4]
    assert_no_match(/write-up/i, bodies.join)
  end

  test "names the channel plainly when the workspace has none stored" do
    @incident.workspace.update!(incidents_channel_id: nil)

    assert_match "#incidents", Slack::Messages::FirstIncidentWalkthrough.build(@incident, step: 1).third.dig(:text, :text)
  end
end
