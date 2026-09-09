require "test_helper"

class Interactions::SubscribeIncidentHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "the first click subscribes and says so where the person clicked" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      channel_id: @workspace.incidents_channel_id,
      user_id: @alice.platform_user_id,
      text: Interactions::SubscribeIncidentHandler.notice(@incident, true)
    ).once

    assert_nil Interactions::SubscribeIncidentHandler.execute(build_interaction)
    assert @incident.subscribed?(@alice)
  end

  test "the second click unsubscribes" do
    @incident.subscribe!(@alice)
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      has_entries(text: Interactions::SubscribeIncidentHandler.notice(@incident, false))
    ).once

    Interactions::SubscribeIncidentHandler.execute(build_interaction)

    assert_not @incident.subscribed?(@alice)
  end

  test "a failed notice does not undo the subscription" do
    Slack::WorkspaceAdapter.any_instance.stubs(:post_ephemeral).raises(AdapterError::NotFound, "channel_not_found")

    assert_nil Interactions::SubscribeIncidentHandler.execute(build_interaction)
    assert @incident.subscribed?(@alice)
  end

  test "the notices are finished sentences with no dashes or semicolons" do
    [ true, false ].each do |subscribed|
      text = Interactions::SubscribeIncidentHandler.notice(@incident, subscribed)
      assert_match(/\.\z/, text)
      assert_no_match(/[;\u2014]/, text)
    end
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @alice.platform_user_id,
      action_id: Identifiers::SUBSCRIBE_INCIDENT,
      action_value: @incident.id,
      channel_id: @workspace.incidents_channel_id
    )
  end
end
