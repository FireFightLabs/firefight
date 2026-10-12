require "test_helper"

# A long chat resends everything it holds on every call, so what the provider cached and where OpenRouter routes it both
# rest on the start of the request staying the same from turn to turn. What changes between turns rides after the chat.
class Conversation::StablePromptTest < ActiveSupport::TestCase
  include FakeProviderHelper

  class CoreRead < RubyLLM::Tool
    description "Reads core"

    def name = "core_read"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def call(tool_call: nil, **) = "core is fine"
  end

  setup do
    FakeProviderHelper::Adapter.reset!
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "two turns around a new plan send the same instructions and opening, the plan last, and the chat's session" do
    choice = openrouter
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: choice)

    turn(chat, choice, "Is checkout healthy?", reply: "Yes.")
    Chat::Plan.make!(chat: chat, made_by: @member, goal: "Release main", steps: [ { "kind" => "check", "description" => "Check checkout" },
                                                                                     { "kind" => "check", "description" => "Check payments" } ])
    turn(chat, choice, "Release main when it is.", reply: "Started.")

    first, second = sent_requests.map { |request| request[:body] }
    assert_equal 2, sent_requests.size
    assert_equal system_of(first).to_json, system_of(second).to_json, "the instructions are byte for byte the same"
    assert_equal opening_of(first).to_json, opening_of(second).to_json, "the first message after them is too"
    assert_equal first["messages"][0..-2].to_json, second["messages"][0...(first["messages"].size - 1)].to_json,
                 "the history the first turn sent is the start of the second, without the first turn's context"

    [ first, second ].each do |body|
      assert_equal chat.id, body["session_id"]
      assert_nil body.dig("provider", "order")
      assert body["messages"].last["content"].to_s.start_with?(FirefightAi::Responder::CONTEXT_HEADING)
    end
    assert_no_match "Release main", first["messages"].last["content"].to_s
    assert_match "Release main", second["messages"].last["content"].to_s
    assert_no_match "Release main", system_of(second).to_json

    assert_not chat.messages.where("content LIKE ?", "#{FirefightAi::Responder::CONTEXT_HEADING}%").exists?, "the context is never saved"
    assert_equal [ "Is checkout healthy?", "Yes.", "Release main when it is.", "Started." ],
                 chat.messages.where.not(role: Chat::Message::ROLE_SYSTEM).map(&:content)
  end

  test "a chat on Anthropic caches the history up to the context, never the context, within the four boundaries" do
    choice = anthropic
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: choice)

    turn(chat, choice, "Is checkout healthy?", reply: "Yes.", anthropic: true)
    turn(chat, choice, "And payments?", reply: "Also yes.", anthropic: true)

    second = sent_requests.last[:body]
    boundaries = second.to_json.scan("\"cache_control\"").size
    before_context = second["messages"][-2]

    assert_operator boundaries, :<=, 4
    assert_equal({ "type" => "ephemeral" }, Array(before_context["content"]).last["cache_control"], "the question before the context ends a boundary")
    assert(Array(second["messages"].last["content"]).none? { |block| block.is_a?(Hash) && block["cache_control"] })
    assert_nil second["session_id"], "only OpenRouter is told a session"
    assert_equal 0, Array(sent_requests.first[:body]["messages"].first["content"]).count { |block| block.is_a?(Hash) && block["cache_control"] },
                 "the opening is never marked, so it is sent the same on every turn"
    assert_nil chat.to_llm.messages.find { |message| message.role == :user && message.cache_until_here? }, "no mark outlives its call"
  end

  test "within a turn the context follows the tool results, and the round before it is saved as it happened" do
    choice = anthropic
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: choice)
    chat.add_message(role: :user, content: "Read core")
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_1", name: "core_read", input: {} } ], usage: { input_tokens: 5, output_tokens: 5 } })
    answer_with(anthropic_reply("Core is fine."))

    FirefightAi::Responder.new(@workspace, inferable: @conversation, member: @member, model: choice).run(
      chat: chat, tools: [ CoreRead.new ], context: "You are acting for Alice.",
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5)
    )

    second = sent_requests.last[:body]["messages"]
    assert_equal "#{FirefightAi::Responder::CONTEXT_HEADING}\nYou are acting for Alice.", Array(second.last["content"]).last["text"]
    result = Array(second[-2]["content"]).find { |block| block["type"] == "tool_result" }
    assert_equal "toolu_1", result["tool_use_id"]
    assert_equal({ "type" => "ephemeral" }, Array(second[-2]["content"]).last["cache_control"])
    assert_equal [ "user", "assistant", "tool", "assistant" ], chat.messages.where.not(role: Chat::Message::ROLE_SYSTEM).map(&:role)
  end

  test "a chat read back for the bench keeps who it acted for, though its context was never saved" do
    choice = openrouter
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: choice)
    turn(chat, choice, "Is checkout healthy?", reply: "Yes.")
    call = RubyLLM::ToolCall.new(id: "call_1", name: "core_read", arguments: {})
    chat.add_message(role: :assistant, content: "", tool_calls: { "call_1" => call })
    chat.add_message(role: :tool, content: "core is fine", tool_call_id: "call_1")

    captured = assert_no_difference("Chat::MemoryUse.count", "reading it back counts no memory as used") do
      Conversation::Rehearsal.capture(@conversation.reload)
    end

    assert captured.context.start_with?("You are acting for #{@member.display_name}")
  end

  test "a chat moved off OpenRouter by a backup stops naming its session" do
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: openrouter)
    FirefightAi.bind(chat, openrouter)
    assert_equal({ session_id: chat.id }, chat.to_llm.provider_options)

    FirefightAi.bind(chat, anthropic)

    assert_empty chat.to_llm.provider_options
  end

  private

  def turn(chat, choice, question, reply:, anthropic: false)
    chat.add_message(role: :user, content: question)
    anthropic ? answer_with(anthropic_reply(reply)) : answer_with(openrouter_reply(reply))
    context = Conversation::Context.new(@conversation.reload, Conversation::Turn.new(@conversation, asker: @member))
    FirefightAi::Responder.new(@workspace, inferable: @conversation, member: @member, model: choice).run(
      chat: chat, tools: [], stable_context: context.stable, context: context.current,
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5)
    )
  end

  def system_of(body) = body["system"] || body["messages"].find { |message| %w[system developer].include?(message["role"]) }

  def opening_of(body) = body["messages"].find { |message| !%w[system developer].include?(message["role"]) }

  def openrouter_reply(text)
    { id: "gen-#{SecureRandom.hex(4)}", object: "chat.completion", model: "anthropic/claude-haiku-5.5",
      choices: [ { index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 20, completion_tokens: 2 } }
  end

  def anthropic_reply(text)
    { id: "msg_#{SecureRandom.hex(4)}", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "end_turn",
      content: [ { type: "text", text: text } ], usage: { input_tokens: 20, output_tokens: 2 } }
  end

  def anthropic = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: "sk-ant-test"))

  def openrouter
    FirefightAi::ModelChoice.new(model: "anthropic/claude-haiku-5.5", provider: "openrouter", context: fake_provider_context(openrouter_api_key: "sk-or-test"))
  end
end
