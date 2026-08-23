require "test_helper"

class Interactions::CreateActionItemFromReactionHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace, declared_by: @member, incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1), name: "Test incident", is_private: false,
      channel_id: "C_TEST_INCIDENT", source: Incident::SOURCE_SLACK
    )
  end

  test "opens the form named by the reaction with the source message carried along" do
    { Identifiers::CREATE_ACTION_FROM_REACTION => Identifiers::CREATE_ACTION_MODAL,
      Identifiers::CREATE_FOLLOWUP_FROM_REACTION => Identifiers::CREATE_FOLLOWUP_MODAL }.each do |action_id, callback_id|
      Slack::Client.expects(:open_modal).with do |args|
        view = args[:view]
        view[:callback_id] == callback_id &&
          Slack::PrivateMetadata.parse(view[:private_metadata]).source_message_link == "https://workspace.slack.com/archives/C123/p123" &&
          view[:blocks].first.dig(:element, :initial_value) == "The database is slow"
      end.returns({ ok: true, view: { id: "V12345678" } })

      assert_nil Interactions::CreateActionItemFromReactionHandler.execute(build_interaction(action_id: action_id, incident_id: @incident.id))
    end
  end

  test "handles a missing incident silently" do
    assert_nil Interactions::CreateActionItemFromReactionHandler.execute(
      build_interaction(action_id: Identifiers::CREATE_ACTION_FROM_REACTION, incident_id: SecureRandom.uuid)
    )
  end

  private

  def build_interaction(action_id:, incident_id:)
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
      user_id: @member.platform_user_id, action_id: action_id, trigger_id: "12345.trigger",
      action_value: { incident_id: incident_id, source_message_text: "The database is slow",
                      source_message_link: "https://workspace.slack.com/archives/C123/p123" }.to_json
    )
  end
end
