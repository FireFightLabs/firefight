require "test_helper"

class Interactions::DeclareIncidentButtonHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "opens the incident creation modal as a test incident from the button's trigger" do
    Slack::WorkspaceAdapter.any_instance.expects(:build_modal)
      .with(PlatformAdapter::Modal::INCIDENT_CREATION, metadata: ModalState.encode(test: true), test: true).returns({ type: "modal" })
    Slack::WorkspaceAdapter.any_instance.expects(:open_modal).with(trigger_id: "trigger-1", view: { type: "modal" }).once

    result = Interactions::DeclareIncidentButtonHandler.execute(
      Interaction.new(
        platform: Platforms::SLACK,
        type: Interaction::BLOCK_ACTIONS,
        team_id: @workspace.platform_id,
        user_id: "U12345678",
        trigger_id: "trigger-1",
        channel_id: "C_INCIDENTS",
        action_id: Identifiers::DECLARE_INCIDENT_FROM_WELCOME
      )
    )

    assert_nil result
  end
end
