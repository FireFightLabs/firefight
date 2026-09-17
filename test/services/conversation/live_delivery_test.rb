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

  test "a tool lands after the text written before it" do
    @delivery.chunk("Let me check.")

    @delivery.step(key: "call_1", title: "Search incidents", status: :running)

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
