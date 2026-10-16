require "test_helper"

class Interactions::StopWatchHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @thread = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @alice, channel_id: "C9", thread_id: "5.5",
                                               max_turns: 5, max_spend_cents: 100)
    @watch = Chat::Watch.create!(chat: @thread.chat_record, workspace: @workspace, asker: @alice, title: "release run #46",
                                 expires_at: 1.hour.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT)
    @update = @watch.updates.create!(kind: Chat::Watch::Update::KIND_PROGRESS, text: "Release run: tag passed.")
    @adapter = stub(post_watch_card: { message_id: "5.8", channel_id: "D1" }, post_watch_end: { message_id: "5.9", channel_id: "C9" },
                    direct_conversation?: false, update_watch_card: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
  end

  test "anyone in the channel stops the watch from its card, which is redrawn without Stop, and the asker is told in a line of its own" do
    @watch.update_columns(thread_card_channel_id: "C9", thread_card_message_id: "5.7")
    @adapter.expects(:update_watch_card).once.with do |channel_id:, message_id:, card:|
      [ channel_id, message_id, card.status, card.live?, card.why ] == [ "C9", "5.7", Chat::Watch::STATUS_STOPPED, false, "Stopped by #{@bob.display_name}." ]
    end
    @adapter.expects(:post_watch_end).with { |channel_id:, thread_id:, card:| channel_id == "C9" && thread_id == "5.5" && card.state == "Stopped" }
    @adapter.expects(:post_watch_end).with { |channel_id:, thread_id:, **| channel_id == @alice.platform_user_id && thread_id.nil? }
    @adapter.expects(:post_ephemeral).never

    Interactions::StopWatchHandler.execute(press(@bob))

    assert_equal [ Chat::Watch::STATUS_STOPPED, @bob ], [ @watch.reload.status, @watch.stopped_by ]
  end

  test "a press after the watch ended says so to whoever pressed and takes Stop off that message too" do
    Conversation::Watches.stop!(@watch, by: @alice)

    @adapter.expects(:update_watch_card).once.with { |channel_id:, message_id:, card:| [ channel_id, message_id, card.live? ] == [ "C9", "5.7", false ] }
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @bob.platform_user_id, text: Chat::Watch::NOTHING_TO_STOP)

    Interactions::StopWatchHandler.execute(press(@bob))
  end

  test "a personal chat's watch is its owner's alone, so another person is told who can stop it and the message keeps Stop" do
    personal = Conversation.start_personal!(workspace: @workspace, member: @alice)
    watch = Chat::Watch.create!(chat: personal.chat_record, workspace: @workspace, asker: @alice, title: "the deploy",
                                expires_at: 1.hour.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT)
    update = watch.updates.create!(kind: Chat::Watch::Update::KIND_STARTED, text: "Watching the deploy.")

    @adapter.expects(:update_watch_card).never
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @bob.platform_user_id,
                                           text: "Only #{@alice.display_name} or whoever this chat belongs to can stop this watch.")

    Interactions::StopWatchHandler.execute(press(@bob, value: update.id))
    assert watch.reload.active?
  end

  test "a line from another workspace's watch is ignored" do
    @adapter.expects(:post_ephemeral).never

    assert_nil Interactions::StopWatchHandler.execute(press(@bob, value: SecureRandom.uuid))
    assert @watch.reload.active?
  end

  test "the dispatcher routes Stop to this handler" do
    assert_equal Interactions::StopWatchHandler, InteractionDispatcher::BLOCK_ACTION_HANDLERS.fetch(Identifiers::WATCH_STOP)
  end

  private

  def press(member, value: @update.id)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: member.platform_user_id,
                    action_id: Identifiers::WATCH_STOP, action_value: value, channel_id: "C9", message_id: "5.7")
  end
end
