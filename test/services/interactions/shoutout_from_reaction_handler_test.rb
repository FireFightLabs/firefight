require "test_helper"

class Interactions::ShoutoutFromReactionHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )
  end

  test "opens shoutout modal" do
    stub_open_modal

    Slack::Client.expects(:open_modal).once.returns({ ok: true, view: { id: "V12345678" } })

    result = Interactions::ShoutoutFromReactionHandler.execute(build_interaction)

    assert_nil result
  end

  test "handles missing incident silently" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::SHOUTOUT_FROM_REACTION,
      action_value: { incident_id: SecureRandom.uuid }.to_json,
      trigger_id: "12345.trigger"
    )

    result = Interactions::ShoutoutFromReactionHandler.execute(interaction)

    assert_nil result
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::SHOUTOUT_FROM_REACTION,
      action_value: { incident_id: @incident.id }.to_json,
      trigger_id: "12345.trigger"
    )
  end
end
