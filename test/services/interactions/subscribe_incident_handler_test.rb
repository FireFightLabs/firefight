require "test_helper"

class Interactions::SubscribeIncidentHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "the first click subscribes and confirms where the person clicked" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_subscription_notice).with(
      channel_id: @workspace.incidents_channel_id,
      user_id: @alice.platform_user_id,
      incident: @incident,
      state: Incident::Subscriptions::SUBSCRIBED
    ).once

    assert_nil Interactions::SubscribeIncidentHandler.execute(build_interaction(Identifiers::SUBSCRIBE_INCIDENT))
    assert @incident.subscribed?(@alice)
  end

  test "a second click says the person is already subscribed and leaves them subscribed" do
    @incident.subscribe!(@alice)
    Slack::WorkspaceAdapter.any_instance.expects(:post_subscription_notice)
      .with(has_entries(state: Incident::Subscriptions::ALREADY_SUBSCRIBED)).once

    Interactions::SubscribeIncidentHandler.execute(build_interaction(Identifiers::SUBSCRIBE_INCIDENT))

    assert @incident.subscribed?(@alice)
  end

  test "unsubscribe removes the subscription and says so" do
    @incident.subscribe!(@alice)
    Slack::WorkspaceAdapter.any_instance.expects(:post_subscription_notice)
      .with(has_entries(state: Incident::Subscriptions::UNSUBSCRIBED)).once

    assert_nil Interactions::UnsubscribeIncidentHandler.execute(build_interaction(Identifiers::UNSUBSCRIBE_INCIDENT))
    assert_not @incident.subscribed?(@alice)
  end

  test "a notice that cannot be delivered does not undo the click" do
    Slack::WorkspaceAdapter.any_instance.stubs(:post_subscription_notice).raises(AdapterError::NotFound, "channel_not_found")

    assert_nil Interactions::SubscribeIncidentHandler.execute(build_interaction(Identifiers::SUBSCRIBE_INCIDENT))
    assert @incident.subscribed?(@alice)
  end

  private

  def build_interaction(action_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @alice.platform_user_id,
      action_id: action_id,
      action_value: @incident.id,
      channel_id: @workspace.incidents_channel_id
    )
  end
end
