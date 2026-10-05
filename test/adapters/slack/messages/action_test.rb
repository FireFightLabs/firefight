require "test_helper"

class Slack::Messages::ActionTest < ActiveSupport::TestCase
  setup do
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a follow-up tracked in an issue links to it, with the tracker's title escaped" do
    action = @incident.incident_actions.create!(
      created_by: @member, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
      description: "Block <!channel> probes", external_key: "FIR-105", external_url: "https://linear.app/firefight/issue/FIR-105"
    )

    body = Slack::Messages::Action.created(action).map { |block| block.dig(:text, :text).to_s }.find { |text| text.start_with?(">") }

    assert_equal "> Block &lt;!channel&gt; probes  ·  <https://linear.app/firefight/issue/FIR-105|FIR-105>", body
  end

  test "an item typed by a person reads as it always has" do
    action = @incident.incident_actions.create!(created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Roll back *now*")

    assert_equal "Roll back *now*", Slack::Messages::Action.described(action)
  end
end
