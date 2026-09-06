require "test_helper"

class Interactions::ResolveIncidentButtonHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens the close dialog for an open incident" do
    ModalOpener.expects(:open).with(:close, workspace: @workspace, incident: @incident, trigger_id: "trig", user_id: "U12345678").once

    assert_nil Interactions::ResolveIncidentButtonHandler.execute(build_interaction(@incident))
  end

  test "an incident that is already over gets a notice instead" do
    resolved = incidents(:resolved_minor_ws1)
    ModalOpener.expects(:open).never
    Interactions::TerminalNotice.expects(:post).with(@workspace, resolved, "U12345678", "#{resolved.identifier} is already over.").once

    Interactions::ResolveIncidentButtonHandler.execute(build_interaction(resolved))
  end

  private

  def build_interaction(incident)
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
      user_id: "U12345678", trigger_id: "trig", channel_id: incident.channel_id,
      action_id: Identifiers::RESOLVE_INCIDENT, action_value: incident.id
    )
  end
end
