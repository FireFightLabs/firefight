require "test_helper"

class Interactions::EscalateIncidentButtonHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "opens escalate modal" do
    ModalOpener.expects(:open).with(
      :escalate,
      workspace: @workspace,
      incident: @incident,
      trigger_id: "12345.trigger",
      user_id: @member.platform_user_id
    ).once

    result = Interactions::EscalateIncidentButtonHandler.execute(build_interaction)

    assert_nil result
  end

  test "explains itself instead of opening the modal on a closed incident" do
    @incident.update!(incident_status: incident_statuses(:resolved_ws1))
    ModalOpener.expects(:open).never
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      channel_id: @incident.channel_id,
      user_id: @member.platform_user_id,
      text: "#{@incident.identifier} is closed, so it can no longer be escalated."
    ).once

    assert_nil Interactions::EscalateIncidentButtonHandler.execute(build_interaction)
  end

  test "explains itself instead of opening the modal on a canceled incident" do
    @incident.update!(incident_status: incident_statuses(:canceled_ws1))
    ModalOpener.expects(:open).never
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      channel_id: @incident.channel_id,
      user_id: @member.platform_user_id,
      text: "#{@incident.identifier} is canceled, so it can no longer be escalated."
    ).once

    assert_nil Interactions::EscalateIncidentButtonHandler.execute(build_interaction)
  end

  test "handles trigger expiration gracefully" do
    ModalOpener.expects(:open).raises(AdapterError::TriggerExpired.new("expired"))

    result = Interactions::EscalateIncidentButtonHandler.execute(build_interaction)

    assert_nil result
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      trigger_id: "12345.trigger",
      action_id: Identifiers::ESCALATE_INCIDENT,
      action_value: @incident.id,
      channel_id: @incident.channel_id
    )
  end
end
