require "test_helper"

class Conversation::LiveDeliveryTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(
      workspace: @workspace, member: workspace_memberships(:alice_workspace_one)
    )
    @delivery = Conversation::LiveDelivery.new(@conversation)
  end

  test "the page hears that a turn has started" do
    assert_broadcast_on(stream, { "type" => Conversation::LiveDelivery::EVENT_THINKING }) do
      @delivery.thinking!
    end
  end

  test "text is held for a moment and sent in pieces rather than token by token" do
    assert_no_broadcasts(stream) do
      @delivery.chunk("The 14:02 ")
      @delivery.chunk("deploy")
    end

    assert_broadcast_on(stream, { "type" => Conversation::LiveDelivery::EVENT_CHUNK, "text" => "The 14:02 deploy" }) do
      @delivery.answered!("The 14:02 deploy")
    end
  end

  test "making room lands where it happened, after the text before it, with its time and never the agent's note" do
    chat = @workspace.chats.create!(owner: @conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    compaction = chat.compactions.create!(stage: Chat::Compaction::STAGE_REBUILT, tokens_before: 150_000, note: "The pool config looks guilty")
    @delivery.chunk("Let me check.")

    @delivery.made_room(compaction)

    sent = broadcasts(stream).map { |message| JSON.parse(message) }
    assert_equal [ Conversation::LiveDelivery::EVENT_CHUNK, Conversation::LiveDelivery::EVENT_MADE_ROOM ], sent.map { |event| event["type"] }
    assert_equal({ "type" => Conversation::LiveDelivery::EVENT_MADE_ROOM, "key" => compaction.step_key, "title" => Chat::Compaction::SHOWN_AS,
                   "at" => compaction.created_at.utc.iso8601(3) }, sent.last)
  end

  test "a tool lands after the text written before it" do
    @delivery.chunk("Let me check.")

    @delivery.step(key: "call_1", step: Chat::Tools.step("search_incidents", { "query" => "checkout" }), status: :running)

    assert_equal(
      [ Conversation::LiveDelivery::EVENT_CHUNK, Conversation::LiveDelivery::EVENT_STEP ],
      broadcasts(stream).map { |message| JSON.parse(message)["type"] }
    )
  end

  test "a turn that died says so, so the page stops waiting" do
    assert_broadcast_on(stream, { "type" => Conversation::LiveDelivery::EVENT_FAILED }) do
      @delivery.failed!
    end
  end

  private

  def stream = ConversationChannel.broadcasting_for(@conversation)
end
