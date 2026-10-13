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
          ModalState.parse(view[:private_metadata]).source_message_link == "https://workspace.slack.com/archives/C123/p123" &&
          ModalState.parse(view[:private_metadata]).prompt_handle == "https://hooks.slack.com/actions/T123/456/abc" &&
          view[:blocks].first.dig(:element, :initial_value) == "The database is slow"
      end.returns({ ok: true, view: { id: "V12345678" } })

      assert_nil Interactions::CreateActionItemFromReactionHandler.execute(build_interaction(action_id: action_id, incident_id: @incident.id))
    end
  end

  test "the description starts from the message as readable text, never Slack's own markup" do
    bob = workspace_memberships(:bob_workspace_one)
    raw = "<@#{bob.platform_user_id}> *roll back* <https://deploys.example.com/42|deploy 42> &amp; check :fire:"
    Slack::Client.expects(:open_modal).with do |args|
      args[:view][:blocks].first.dig(:element, :initial_value) == "@#{bob.display_name} roll back deploy 42 (https://deploys.example.com/42) & check 🔥"
    end.returns({ ok: true, view: { id: "V12345678" } })

    assert_nil Interactions::CreateActionItemFromReactionHandler.execute(
      build_interaction(action_id: Identifiers::CREATE_ACTION_FROM_REACTION, incident_id: @incident.id, text: raw)
    )
  end

  test "the form reads the message it was opened for when it opens, as readable text up to the form's own limit" do
    bob = workspace_memberships(:bob_workspace_one)
    Slack::Client.expects(:get_message).with { |arguments| arguments[:channel] == "C123" && arguments[:ts] == "1700000000.000100" }
                 .returns({ "ts" => "1700000000.000100", "user" => bob.platform_user_id, "text" => "<@#{bob.platform_user_id}> #{'slow ' * 1000}" })
    Slack::Client.expects(:open_modal).with do |args|
      initial = args[:view][:blocks].first.dig(:element, :initial_value)
      initial.start_with?("@#{bob.display_name} slow slow") && initial.length == Slack::Modals::ActionItemsForm::DESCRIPTION_LIMIT
    end.returns({ ok: true, view: { id: "V12345678" } })

    assert_nil Interactions::CreateActionItemFromReactionHandler.execute(
      build_interaction(action_id: Identifiers::CREATE_ACTION_FROM_REACTION, incident_id: @incident.id, text: nil,
                        channel_id: "C123", message_id: "1700000000.000100")
    )
  end

  test "a message that can no longer be read opens the form empty" do
    Slack::WorkspaceAdapter.any_instance.stubs(:fetch_message).raises(AdapterError::NotFound.new("message_not_found"))
    Slack::Client.expects(:open_modal).with { |args| !args[:view][:blocks].first[:element].key?(:initial_value) }.returns({ ok: true, view: { id: "V1" } })

    assert_nil Interactions::CreateActionItemFromReactionHandler.execute(
      build_interaction(action_id: Identifiers::CREATE_ACTION_FROM_REACTION, incident_id: @incident.id, text: nil,
                        channel_id: "C123", message_id: "1700000000.000100")
    )
  end

  test "handles a missing incident silently" do
    assert_nil Interactions::CreateActionItemFromReactionHandler.execute(
      build_interaction(action_id: Identifiers::CREATE_ACTION_FROM_REACTION, incident_id: SecureRandom.uuid)
    )
  end

  private

  def build_interaction(action_id:, incident_id:, text: "The database is slow", channel_id: nil, message_id: nil)
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
      user_id: @member.platform_user_id, action_id: action_id, trigger_id: "12345.trigger",
      prompt_handle: "https://hooks.slack.com/actions/T123/456/abc",
      action_value: { incident_id: incident_id, source_message_text: text, channel_id: channel_id, message_id: message_id,
                      source_message_link: "https://workspace.slack.com/archives/C123/p123" }.compact.to_json
    )
  end
end
