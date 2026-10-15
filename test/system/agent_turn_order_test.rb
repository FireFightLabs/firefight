require "application_system_test_case"

class AgentTurnOrderTest < ApplicationSystemTestCase
  PLAN = "Plan: fix 8 review comments on PR 14, then reply to each.".freeze
  UPDATE = "I'm going to update the PR now.".freeze
  RESULT = "Updated the PR and replied to all 8 comments.".freeze

  # The test adapter only records broadcasts, and this test needs the browser to receive one.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
    workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
    @conversation = Conversation.start_personal!(workspace: workspace, member: workspace_memberships(:alice_workspace_one))
    @conversation.ask!("Fix the review comments on PR 14")
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "a turn reads in the order it happened, its notes fold with its work, and a reload reads the same" do
    visit agent_chat_path(@conversation)
    assert_text "Fix the review comments"
    delivery = Conversation::LiveDelivery.new(@conversation)
    open_stream(delivery)

    delivery.chunk(PLAN)
    reads = %w[call_1 call_2 call_3].map { |key| [ key, Chat::Tools.step("search_incidents", { "query" => "review #{key}" }) ] }
    reads.each { |key, step| delivery.step(key: key, step: step, status: :running, kind: Chat::Tools::KIND_READ) }
    reads.each { |key, step| delivery.step(key: key, step: step, status: :done, kind: Chat::Tools::KIND_READ) }
    delivery.chunk(UPDATE)
    fix = Chat::Tools.step("declare_incident", { "name" => "Update PR 14" })
    delivery.step(key: "call_4", step: fix, status: :running)

    assert_text "Looked at 3 things"
    assert_text(/#{Regexp.escape(PLAN)}.*Looked at 3 things.*#{Regexp.escape(UPDATE)}.*Declare incident.*Working/m)
    assert_no_text "Search incidents"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-turn-order-live.png"))

    find("button", text: "Looked at 3 things").click
    assert_text(/Looked at 3 things.*Search incidents.*Search incidents.*Search incidents.*#{Regexp.escape(UPDATE)}/m)

    save_turn
    delivery.step(key: "call_4", step: fix, status: :done)
    @conversation.reply_delivered!
    delivery.answered!(RESULT)

    assert_text RESULT
    assert_folded
    assert_text(/Worked for 5m 36s · 4 steps.*#{Regexp.escape(RESULT)}/m)
    assert_equal [ RESULT, "Read 3 sources" ], said_after_work, "the result is followed only by the sources it read"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-turn-order-folded.png"))

    find("button", text: /Worked for/).click
    assert_text(/#{Regexp.escape(PLAN)}.*Search incidents.*#{Regexp.escape(UPDATE)}.*Declare incident.*#{Regexp.escape(RESULT)}/m)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-turn-order-opened.png"))

    visit agent_chat_path(@conversation)
    assert_text RESULT
    assert_folded
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-turn-order-reloaded.png"))

    page.current_window.resize_to(390, 844)
    find("button", text: /Worked for/).click
    assert_text(/#{Regexp.escape(PLAN)}.*#{Regexp.escape(UPDATE)}.*#{Regexp.escape(RESULT)}/m)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-turn-order-phone.png"))
  end

  test "words that put a change to the person stay a message where they were asked" do
    chat = @conversation.chat_record
    asked = chat.add_message(RubyLLM::Message.new(
      role: :assistant, content: "Checkout needs a restart. Can I restart it?",
      tool_calls: { "call_9" => RubyLLM::ToolCall.new(id: "call_9", name: "search_incidents", arguments: { "query" => "checkout" }) }
    ))
    chat.request_decisions!([ "call_9" ])
    chat.decide!("call_9", approved: true)
    chat.add_message(role: :tool, content: "restarted", tool_call_id: "call_9")
    chat.add_message(role: :assistant, content: "Restarted checkout, it is healthy again.")
    @conversation.reply_delivered!
    assert asked

    visit agent_chat_path(@conversation)

    assert_text(/Checkout needs a restart. Can I restart it\?.*Worked for.*Restarted checkout/m)
    assert_equal [ "Checkout needs a restart. Can I restart it?", "Worked for a moment · 1 step", "Restarted checkout, it is healthy again." ],
                 turn_parts.first(3), "the question is said in the turn, outside the folded work"
  end

  private

  # What the finished turn shows after its folded work, in order.
  def said_after_work = turn_parts.drop(1)

  # Each thing the finished turn shows, in order, the folded work as its one line.
  def turn_parts
    turn = find("button", text: /Worked for/).ancestor("div.flex-col.gap-3", match: :first)
    evaluate_script("Array.from(arguments[0].children).map((child) => child.innerText.trim().split('\\n')[0])", turn)
  end

  def assert_folded
    assert_selector "button", text: "Worked for 5m 36s · 4 steps"
    assert_no_text PLAN
    assert_no_text UPDATE
  end

  # What the loop saves as the turn goes: each message's words with the calls it made, then the turn's last words.
  def save_turn
    chat = @conversation.chat_record
    planned = { "call_1" => "a", "call_2" => "b", "call_3" => "c" }.to_h do |key, query|
      [ key, RubyLLM::ToolCall.new(id: key, name: "search_incidents", arguments: { "query" => "review #{query}" }) ]
    end
    read = chat.add_message(RubyLLM::Message.new(role: :assistant, content: PLAN, tool_calls: planned))
    found = planned.keys.map { |key| chat.add_message(role: :tool, content: "found", tool_call_id: key) }
    fix = { "call_4" => RubyLLM::ToolCall.new(id: "call_4", name: "declare_incident", arguments: { "name" => "Update PR 14" }) }
    updated = chat.add_message(RubyLLM::Message.new(role: :assistant, content: UPDATE, tool_calls: fix))
    done = chat.add_message(role: :tool, content: "done", tool_call_id: "call_4")
    # The reads took five minutes and the update 36 seconds, which the folded line says in minutes and seconds.
    found.last.update_columns(created_at: read.created_at + 5.minutes)
    done.update_columns(created_at: updated.created_at + 36.seconds)
    chat.add_message(role: :assistant, content: RESULT)
  end

  # An accepted subscription can miss what is sent before its stream is live, so the turn is announced until the page shows it.
  def open_stream(delivery)
    50.times do
      delivery.thinking!
      return if page.has_text?("Working", wait: 0.2)
    end

    flunk "the page never opened its socket"
  end
end
