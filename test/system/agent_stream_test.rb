require "application_system_test_case"

class AgentStreamTest < ApplicationSystemTestCase
  # The test adapter only records broadcasts, and this test needs the browser to receive one.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "the answer arrives as it is written" do
    workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
    # The sign in helper stubs the controller, not the session the socket reads, so the socket is stubbed too.
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))

    conversation = Conversation.start_personal!(workspace: workspace, member: member)
    conversation.ask!("Has checkout failed like this before?")

    visit agent_chat_path(conversation)
    assert_text "Has checkout failed"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    similar = Chat::Tools.step("search_similar", { "query" => "checkout failing" })
    delivery.step(key: "call_1", step: similar, status: :running)
    delivery.step(key: "call_1", step: similar, status: :done)
    delivery.step(key: "call_2", step: Chat::Tools.step("search_incidents", { "query" => "checkout" }), status: :running)
    delivery.chunk("Twice in the last quarter. ")
    delivery.chunk("INC-118 was the same connection pool exhaustion.")
    delivery.answered!("ignored")

    assert_text "Search similar"
    assert_text "INC-118 was the same connection pool exhaustion."
  end

  test "a turn says where Halon shortened its working notes, as it happens and once the answer is saved" do
    workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))

    conversation = Conversation.start_personal!(workspace: workspace, member: member)
    conversation.ask!("Has checkout failed like this before?")
    chat = conversation.chat_record

    visit agent_chat_path(conversation)
    assert_text "Has checkout failed"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    similar = Chat::Tools.step("search_similar", { "query" => "checkout failing" })
    delivery.step(key: "call_1", step: similar, status: :running)
    delivery.step(key: "call_1", step: similar, status: :done)
    compaction = chat.compactions.create!(stage: Chat::Compaction::STAGE_REBUILT, tokens_before: 150_000, note: "The pool config looks guilty")
    delivery.made_room(compaction)
    delivery.step(key: "call_2", step: Chat::Tools.step("search_incidents", { "query" => "checkout" }), status: :running)

    assert_text(/Search similar.*#{Chat::Compaction::SHOWN_AS}.*Search incidents/m)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-made-room-live.png"))

    asked = chat.add_message(RubyLLM::Message.new(
      role: :assistant, content: "",
      tool_calls: { "call_3" => RubyLLM::ToolCall.new(id: "call_3", name: "search_incidents", arguments: { "query" => "checkout" }) }
    ))
    chat.add_message(role: :tool, content: "INC-118", tool_call_id: "call_3")
    chat.add_message(role: :assistant, content: "INC-118 was the same connection pool exhaustion.")
    compaction.update!(created_at: asked.created_at - 1.second)
    conversation.reply_delivered!
    delivery.answered!("ignored")

    assert_text "INC-118 was the same connection pool exhaustion."
    find("button", text: /Worked for/).click
    assert_text(/#{Chat::Compaction::SHOWN_AS}.*Search incidents/m)
    assert_text(/1 step/)
    assert_no_text "The pool config looks guilty"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-made-room-saved.png"))
  end

  test "events that reach the page out of order still show in the order they were sent" do
    workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
    conversation = Conversation.start_personal!(workspace: workspace, member: member)
    conversation.ask!("Has checkout failed like this before?")

    visit agent_chat_path(conversation)
    assert_text "Has checkout failed"
    open_stream(Conversation::LiveDelivery.new(conversation))

    # Action Cable's thread pool can deliver a turn's broadcasts in any order, so they are sent here scrambled.
    sent = 10.seconds.from_now.to_i * 1_000_000
    event = ->(seq, payload) { ConversationChannel.broadcast_to(conversation, payload.merge(seq: sent + seq)) }
    step = ->(key, tool, status) { { type: Conversation::LiveDelivery::EVENT_STEP, key: key, title: Chat::Tools.step(tool, { "query" => "checkout" }).title, status: status } }
    event.call(6, { type: Conversation::LiveDelivery::EVENT_CHUNK, text: "the same pool." })
    event.call(4, step.call("call_2", "search_incidents", Conversation::LiveDelivery::STATUS_RUNNING))
    event.call(2, step.call("call_1", "search_similar", Conversation::LiveDelivery::STATUS_DONE))
    event.call(3, { type: Conversation::LiveDelivery::EVENT_MADE_ROOM, key: "room-1", title: Chat::Compaction::SHOWN_AS, at: Time.current.utc.iso8601(3) })
    event.call(5, { type: Conversation::LiveDelivery::EVENT_CHUNK, text: "INC-118 was " })
    event.call(1, step.call("call_1", "search_similar", Conversation::LiveDelivery::STATUS_RUNNING))
    event.call(0, { type: Conversation::LiveDelivery::EVENT_THINKING })

    assert_text(/Search similar.*#{Chat::Compaction::SHOWN_AS}.*Search incidents/m)
    assert_text "INC-118 was the same pool."
    assert_selector :xpath, "//*[normalize-space(text())='Running']", count: 1
  end

  private

  # An accepted subscription can miss what is sent before its stream is live, so the turn is announced until the page shows it.
  def open_stream(delivery)
    50.times do
      delivery.thinking!
      return if page.has_text?("Working", wait: 0.2)
    end

    flunk "the page never opened its socket"
  end
end
