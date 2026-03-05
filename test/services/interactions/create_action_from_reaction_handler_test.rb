require "test_helper"

class Interactions::CreateActionFromReactionHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )
  end

  test "opens pre-filled create action modal" do
    stub_open_modal

    Slack::Client.expects(:open_modal).once.returns({ ok: true, view: { id: "V12345678" } })

    result = Interactions::CreateActionFromReactionHandler.execute(build_interaction)

    assert_nil result
  end

  test "handles missing incident silently" do
    action_value = {
      incident_id: SecureRandom.uuid,
      source_message_text: "Some text",
      source_message_link: "https://example.com"
    }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::CREATE_ACTION_FROM_REACTION,
      action_value: action_value,
      trigger_id: "12345.trigger"
    )

    result = Interactions::CreateActionFromReactionHandler.execute(interaction)

    assert_nil result
  end

  private

  def build_interaction
    action_value = {
      incident_id: @incident.id,
      source_message_text: "The database is slow",
      source_message_link: "https://workspace.slack.com/archives/C123/p123"
    }.to_json

    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::CREATE_ACTION_FROM_REACTION,
      action_value: action_value,
      trigger_id: "12345.trigger"
    )
  end
end
