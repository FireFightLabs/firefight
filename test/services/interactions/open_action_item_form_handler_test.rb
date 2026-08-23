require "test_helper"

class Interactions::OpenActionItemFormHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace, declared_by: @member, incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1), name: "Test incident", is_private: false,
      channel_id: "C_TEST_INCIDENT", source: Incident::SOURCE_SLACK
    )
  end

  test "pushes the form named by the button" do
    { Identifiers::ADD_NEW_ACTION => Identifiers::CREATE_ACTION_MODAL,
      Identifiers::ADD_NEW_FOLLOWUP => Identifiers::CREATE_FOLLOWUP_MODAL }.each do |action_id, callback_id|
      Slack::Client.expects(:push_modal).with { |args| args[:view][:callback_id] == callback_id }
        .returns({ ok: true, view: { id: "V12345678" } })

      assert_nil Interactions::OpenActionItemFormHandler.execute(build_interaction(action_id: action_id, incident_id: @incident.id))
    end
  end

  test "handles a missing incident silently" do
    assert_nil Interactions::OpenActionItemFormHandler.execute(build_interaction(action_id: Identifiers::ADD_NEW_ACTION, incident_id: SecureRandom.uuid))
  end

  private

  def build_interaction(action_id:, incident_id:)
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
      user_id: @member.platform_user_id, action_id: action_id, action_value: incident_id, trigger_id: "12345.trigger"
    )
  end
end
