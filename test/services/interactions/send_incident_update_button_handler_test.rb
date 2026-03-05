require "test_helper"

class Interactions::SendIncidentUpdateButtonHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "opens incident update modal" do
    stub_post_message
    stub_open_modal

    result = Interactions::SendIncidentUpdateButtonHandler.execute(
      build_interaction
    )

    assert_nil result
  end

  test "handles trigger expiration silently" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    stub_delete_message

    result = Interactions::SendIncidentUpdateButtonHandler.execute(
      build_interaction
    )

    assert_nil result
  end

  test "handles missing incident silently" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::SEND_INCIDENT_UPDATE,
      action_value: SecureRandom.uuid,
      trigger_id: "12345.trigger"
    )

    result = Interactions::SendIncidentUpdateButtonHandler.execute(interaction)

    assert_nil result
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::SEND_INCIDENT_UPDATE,
      action_value: @incident.id,
      trigger_id: "12345.trigger"
    )
  end
end
