require "test_helper"

class Interactions::ViewClosedHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "deletes temp message when summary modal is closed" do
    stub_delete_message

    Slack::Client.expects(:delete_message).with(
      workspace: @workspace,
      channel: @incident.slack_channel_id,
      ts: "1234567890.123456"
    ).once

    result = Interactions::ViewClosedHandler.execute(build_interaction)

    assert_nil result
  end

  test "ignores non-summary modal closures" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: "some_other_modal",
      private_metadata: "anything"
    )

    result = Interactions::ViewClosedHandler.execute(interaction)

    assert_nil result
  end

  test "handles missing temp message metadata gracefully" do
    metadata = { incident_id: @incident.id }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
      private_metadata: metadata
    )

    result = Interactions::ViewClosedHandler.execute(interaction)

    assert_nil result
  end

  private

  def build_interaction
    metadata = { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.slack_channel_id }.to_json

    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
      private_metadata: metadata
    )
  end
end
