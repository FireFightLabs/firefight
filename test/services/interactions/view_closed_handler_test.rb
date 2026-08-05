require "test_helper"

class Interactions::ViewClosedHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "deletes temp message when summary modal is closed" do
    stub_delete_message

    Slack::Client.expects(:delete_message).with(
      workspace: @workspace,
      channel: @incident.channel_id,
      ts: "1234567890.123456"
    ).once

    result = Interactions::ViewClosedHandler.execute(build_interaction)

    assert_nil result
  end

  test "deletes temp message when incident update modal is closed" do
    stub_delete_message

    metadata = { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
      private_metadata: metadata
    )

    Slack::Client.expects(:delete_message).with(
      workspace: @workspace,
      channel: @incident.channel_id,
      ts: "1234567890.123456"
    ).once

    result = Interactions::ViewClosedHandler.execute(interaction)

    assert_nil result
  end

  test "deletes temp message when close incident modal is closed" do
    stub_delete_message

    metadata = { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::CLOSE_INCIDENT_MODAL,
      private_metadata: metadata
    )

    Slack::Client.expects(:delete_message).once

    result = Interactions::ViewClosedHandler.execute(interaction)

    assert_nil result
  end

  test "deletes temp message when reopen incident modal is closed" do
    stub_delete_message

    metadata = { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::REOPEN_INCIDENT_MODAL,
      private_metadata: metadata
    )

    Slack::Client.expects(:delete_message).once

    result = Interactions::ViewClosedHandler.execute(interaction)

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
    metadata = { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json

    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_CLOSED,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
      private_metadata: metadata
    )
  end

  # The allowlist this replaced never got Cancel, so closing that modal left
  # "is canceling the incident..." in the channel for good.
  test "deletes the temp message for every modal that opened one" do
    [ Identifiers::CANCEL_INCIDENT_MODAL, Identifiers::CLOSE_INCIDENT_MODAL,
      Identifiers::REOPEN_INCIDENT_MODAL, Identifiers::UPDATE_SUMMARY_MODAL,
      Identifiers::INCIDENT_UPDATE_MODAL, Identifiers::ESCALATE_INCIDENT_MODAL ].each do |callback_id|
      stub_delete_message
      Slack::Client.expects(:delete_message).once

      interaction = Interaction.new(
        platform: Platforms::SLACK,
        type: Interaction::VIEW_CLOSED,
        team_id: @workspace.platform_id,
        user_id: "U12345678",
        callback_id: callback_id,
        private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456",
                            channel_id: @incident.channel_id }.to_json
      )

      assert_nil Interactions::ViewClosedHandler.execute(interaction), callback_id
      mocha_teardown
      mocha_setup
    end
  end
end
