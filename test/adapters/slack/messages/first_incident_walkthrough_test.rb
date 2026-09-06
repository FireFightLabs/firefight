require "test_helper"

class Slack::Messages::FirstIncidentWalkthroughTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "walks through lead, messages and resolve with the script to paste" do
    @incident.workspace.update!(incidents_channel_id: "C_INCIDENTS")
    blocks = Slack::Messages::FirstIncidentWalkthrough.build(@incident)

    assert_equal "section", blocks.first[:type]
    assert_equal "divider", blocks.second[:type]
    body = blocks.third.dig(:text, :text)
    assert_match "Make me Lead", body
    assert_match "<#C_INCIDENTS>", body
    Slack::Messages::FirstIncidentWalkthrough::SCRIPT.each { |line| assert_match line, body }
    assert_match "/ff resolve", body
    assert_equal "context", blocks.last[:type]
  end

  test "names the channel plainly when the workspace has none stored" do
    @incident.workspace.update!(incidents_channel_id: nil)

    assert_match "#incidents", Slack::Messages::FirstIncidentWalkthrough.build(@incident).third.dig(:text, :text)
  end
end
