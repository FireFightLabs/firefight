require "test_helper"

class ConversationReplyJobTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "the turn acts as the person who asked, or whoever started the chat for a job queued without one" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    bob = workspace_memberships(:bob_workspace_one)
    Conversation::Runner.expects(:new).with(conversation, asker: bob).returns(stub(run: nil))
    Conversation::Runner.expects(:new).with(conversation, asker: @member).returns(stub(run: nil))

    ConversationReplyJob.perform_now(conversation.id, bob.id)
    ConversationReplyJob.perform_now(conversation.id)
  end

  test "a dashboard chat hears that the turn died rather than waiting on it" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    Conversation::Runner.any_instance.stubs(:run).raises(FirefightAi::TerminalError, "no model")

    assert_broadcast_on(
      ConversationChannel.broadcasting_for(conversation),
      { "type" => Conversation::LiveDelivery::EVENT_FAILED }
    ) do
      ConversationReplyJob.perform_now(conversation.id)
    end

    assert_equal Conversation::Delivery::FAILED,
                 conversation.reload.chat.messages.where(role: Chat::Message::ROLE_ASSISTANT).sole.content
  end

  test "a thread in Slack is told too" do
    conversation = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C_INCIDENT", thread_id: "1700000000.000100",
      started_by: @member, max_turns: 10, max_spend_cents: 40
    )
    Conversation::Runner.any_instance.stubs(:run).raises(FirefightAi::TerminalError, "no model")
    stub_agent_session
    Slack::Client.expects(:post_message).with do |arguments|
      arguments[:text] == Conversation::Delivery::FAILED
    end.returns({ ok: true, ts: "1" })

    ConversationReplyJob.perform_now(conversation.id)
  end

  test "two questions in one chat are answered one after the other, and two chats are not held up by each other" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    other = Conversation.start_personal!(workspace: @workspace, member: @member)

    first = ConversationReplyJob.new(conversation.id, @member.id)
    second = ConversationReplyJob.new(conversation.id, nil)

    assert_equal 1, ConversationReplyJob.concurrency_limit
    assert_equal first.concurrency_key, second.concurrency_key
    assert_not_equal first.concurrency_key, ConversationReplyJob.new(other.id).concurrency_key
  end

  test "a conversation that is gone is left alone" do
    Conversation::Runner.any_instance.stubs(:run).raises(FirefightAi::TerminalError, "no model")

    assert_nothing_raised { ConversationReplyJob.perform_now(SecureRandom.uuid) }
  end
end
