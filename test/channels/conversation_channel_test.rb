require "test_helper"

class ConversationChannelTest < ActionCable::Channel::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(
      workspace: @workspace, member: workspace_memberships(:alice_workspace_one)
    )
  end

  test "the person who started the chat watches it" do
    stub_connection(current_user: users(:alice))

    subscribe(id: @conversation.id)

    assert subscription.confirmed?
    assert_has_stream_for @conversation
  end

  test "nobody else may watch it, whatever else they can see in the workspace" do
    stub_connection(current_user: users(:bob))

    subscribe(id: @conversation.id)

    assert subscription.rejected?
  end

  test "the person who started it stops watching once they may not read the agent's work" do
    stub_connection(current_user: users(:alice))
    AbilityGateway.stubs(:permitted?).returns(false)

    subscribe(id: @conversation.id)

    assert subscription.rejected?
  end

  test "a channel conversation is not watchable, since it is read in Slack" do
    stub_connection(current_user: users(:alice))
    channel_chat = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "1700000000.000100",
      started_by: workspace_memberships(:alice_workspace_one), max_turns: 10, max_spend_cents: 40
    )

    subscribe(id: channel_chat.id)

    assert subscription.rejected?
  end

  test "an id that is not a conversation is refused" do
    stub_connection(current_user: users(:alice))

    subscribe(id: SecureRandom.uuid)

    assert subscription.rejected?
  end
end
