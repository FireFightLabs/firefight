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
    ModalOpener.expects(:open).with(
      :update,
      workspace: @workspace,
      incident: @incident,
      trigger_id: "12345.trigger",
      user_id: @member.platform_user_id
    ).once

    result = Interactions::SendIncidentUpdateButtonHandler.execute(
      build_interaction
    )

    assert_nil result
  end

  test "handles trigger expiration silently" do
    ModalOpener.expects(:open).raises(AdapterError::TriggerExpired.new("expired"))

    result = Interactions::SendIncidentUpdateButtonHandler.execute(
      build_interaction
    )

    assert_nil result
  end

  test "handles missing incident silently" do
    ModalOpener.expects(:open).never

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
