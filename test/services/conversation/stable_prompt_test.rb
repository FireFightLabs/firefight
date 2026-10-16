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

  # Loads another tool into the chat as open_tools and use_skill do, mid-turn.
  class LoadingRead < CoreRead
    def initialize(chat)
      super()
      @chat = chat
    end

    def call(tool_call: nil, **)
      Chat::Tools.offer_to(@chat).call([ LoadedRead.new ])
      "core is fine, and payments_read is in your hands"
    end
  end

  class LoadedRead < RubyLLM::Tool
    description "Reads payments"

    def name = "payments_read"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def call(tool_call: nil, **) = "payments are fine"
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

  # Seen on a long chat on OpenRouter: a person's message with Firefight's note after it, the note marked as the cache
  # boundary, then a call seconds later that read only the instructions and wrote the other 270,000 tokens again.
  test "every call of a chat sends what the call before it cached as it sent it, across a person's message, Firefight's note and a tool loaded mid-turn" do
    choice = openrouter
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: choice)
    loading = LoadingRead.new(chat)

    chat.add_message(role: :user, content: "Is checkout healthy?")
    answer_with(openrouter_reply("Yes."))
    respond(chat, choice, tools: [ loading ])

    chat.add_message(role: :user, content: "And payments?")
    chat.nudge!("Before this message, your recent answers rested on results that said something could not be used.")
    answer_with(openrouter_tool_call("core_read"))
    answer_with(openrouter_tool_call("payments_read", id: "call_2"))
    answer_with(openrouter_reply("Payments are fine."))
    respond(chat, choice, tools: [ loading ])

    chat.add_message(role: :user, content: "And search?")
    answer_with(openrouter_reply("Search is fine."))
    respond(chat, choice, tools: [ loading, LoadedRead.new ])

    bodies = sent_requests.map { |request| request[:body] }
    assert_equal 5, bodies.size
    bodies.each_cons(2).with_index do |(before, after), index|
      cached = before["messages"].rindex { |message| message["role"] != "developer" && marked?(message) }
      next assert_nil(cached, "the chat's first message is never marked") if index.zero?

      assert cached, "call #{index + 1} marks where its history is cached"
      assert_equal as_cached(before["messages"][0..cached]), as_cached(after["messages"][0..cached]),
                   "call #{index + 2} sends the history call #{index + 1} cached the way it was cached"
    end

    tool_names = bodies.map { |body| body["tools"].map { |tool| tool.dig("function", "name") } }
    assert_equal [ %w[core_read] ] * 2 + [ %w[core_read payments_read] ] * 3, tool_names, "a tool loaded mid-turn is added after the rest"
    assert_equal [ bodies[2]["tools"].to_json ] * 2, [ bodies[3], bodies[4] ].map { |body| body["tools"].to_json }, "the rest of the turn and the next send the tools as the call that loaded one did"
  end

  test "a chat on Anthropic keeps its instructions and the start of each turn for an hour, and every other boundary for five minutes" do
    choice = anthropic
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: choice)
    chat.add_message(role: :user, content: "Is checkout healthy?")
    answer_with(anthropic_reply("Yes."))
    respond(chat, choice, tools: [ CoreRead.new ])

    chat.add_message(role: :user, content: "And payments?")
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_1", name: "core_read", input: {} } ], usage: { input_tokens: 5, output_tokens: 5 } })
    answer_with(anthropic_reply("Payments are fine."))
    respond(chat, choice, tools: [ CoreRead.new ])

    chat.add_message(role: :user, content: "And search?")
    answer_with(anthropic_reply("Search is fine."))
    respond(chat, choice, tools: [ CoreRead.new ])

    hour = { "type" => "ephemeral", "ttl" => "1h" }
    five = { "type" => "ephemeral" }
    _, turn_start, in_turn, next_turn = sent_requests.map { |request| request[:body] }

    assert_equal [ hour, hour ], marks(turn_start), "the instructions and the person's message the turn starts from"
    assert_equal five, turn_start["cache_control"], "the context at the end changes on every call"
    assert_equal [ hour, hour, five ], marks(in_turn), "the held start, then the tool result as a five minute boundary"
    assert_equal [ hour, hour, hour ], marks(next_turn), "the turn before's start, read after a pause, and this turn's"
    [ turn_start, in_turn, next_turn ].each { |body| assert_operator body.to_json.scan("\"cache_control\"").size, :<=, 4 }

    held = chat.messages.where(cache_until_here: true).where.not(role: Chat::Message::ROLE_SYSTEM)
    assert_equal [ "And search?" ], held.map(&:content), "one boundary is held at a time, the newest turn's"
  end

  test "a run that is not a chat keeps every boundary for five minutes" do
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: anthropic)
    chat.add_message(role: :user, content: "Check checkout")
    FirefightAi.ready_chat(chat, choice: anthropic, instructions: "Check what you are asked.", tools: [ CoreRead.new ])
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_1", name: "core_read", input: {} } ], usage: { input_tokens: 5, output_tokens: 5 } })
    answer_with(anthropic_reply("Checkout is fine."))

    FirefightAi::AgentLoop.new(
      chat: chat, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5), answered: -> { false },
      inference: { workspace: @workspace, feature: "test", provider: "anthropic", model: "claude-haiku-4-5" }, choice: anthropic,
      memory: chat, reply_is_answer: true, context: "Now."
    ).run

    assert(sent_requests.all? { |request| request[:body].to_json.exclude?("\"ttl\"") })
    assert_not chat.messages.where(cache_until_here: true).where.not(role: Chat::Message::ROLE_SYSTEM).exists?
  end

  test "a write that lasts an hour is priced at the hour's rate, and OpenRouter's own price for a call is the one recorded" do
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: anthropic)
    chat.add_message(role: :user, content: "Is checkout healthy?")
    answer_with(anthropic_reply("Yes.").merge(usage: { input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 1_000,
                                                       cache_creation: { ephemeral_1h_input_tokens: 1_000, ephemeral_5m_input_tokens: 0 } }))
    respond(chat, anthropic, tools: [])

    inference = Inference.where(inferable: @conversation).sole
    pricing = RubyLLM.models.find("claude-haiku-4-5", provider: "anthropic").pricing.text_tokens.standard
    expected = (10 * pricing.input_per_million) + (1_000 * pricing.input_per_million * 2) + (5 * pricing.output_per_million)
    assert_equal({ "1h" => 1_000 }, inference.cache_write_tokens_by_ttl)
    assert_equal expected.round, inference.cost_micros

    routed = Chat.open!(owner: Conversation.start_personal!(workspace: @workspace, member: @member), workspace: @workspace, model_choice: openrouter)
    routed.add_message(role: :user, content: "Is checkout healthy?")
    answer_with(openrouter_reply("Yes.").merge(usage: { prompt_tokens: 1_210, completion_tokens: 5, cost: 0.0123,
                                                        prompt_tokens_details: { cached_tokens: 0, cache_write_tokens: 1_200 } }))
    FirefightAi::Responder.new(@workspace, inferable: routed.owner, member: @member, model: openrouter).run(
      chat: routed, tools: [], context: "Now.", memory: routed, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5)
    )

    assert_equal 12_300, Inference.where(inferable: routed.owner).sole.cost_micros
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

  # A turn as the runner sends it, with the chat as the loop's memory.
  def respond(chat, choice, tools:)
    FirefightAi::Responder.new(@workspace, inferable: @conversation, member: @member, model: choice).run(
      chat: chat, tools: tools, context: "You are acting for Alice.", memory: chat,
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5)
    )
  end

  def marked?(message) = Array(message["content"]).any? { |block| block.is_a?(Hash) && block["cache_control"] }

  # Every cache_control in the order Anthropic reads them: the instructions, then the messages.
  def marks(body)
    blocks = Array(body["system"]) + body["messages"].flat_map { |message| Array(message["content"]) }
    blocks.filter_map { |block| block["cache_control"] if block.is_a?(Hash) }
  end

  # What a provider caches of messages sent through OpenRouter, as seen on Anthropic's models: the marks are not part of
  # it, and a run of user messages reaches the model as one, plain texts joined into one text and anything sent as blocks
  # kept apart, so a message turned into a block by its mark changes how the run before it is sent.
  def as_cached(messages)
    messages.each_with_object([]) do |message, sent|
      plain = message["content"].is_a?(String)
      texts = plain ? [ message["content"] ] : Array(message["content"]).map { |block| block.except("cache_control") }
      joined = sent.last if message["role"] == "user" && sent.last&.dig(:message, "role") == "user"
      if joined && joined[:plain] && plain
        joined[:texts][-1] = "#{joined[:texts][-1]}\n#{message['content']}"
      elsif joined
        joined[:texts].concat(texts)
        joined[:plain] = false
      else
        sent << { message: message.except("content"), plain: plain, texts: texts }
      end
    end.map { |sent| sent[:message].merge("content" => sent[:texts].map { |text| text.is_a?(Hash) ? text["text"] || text : text }) }
  end

  def system_of(body) = body["system"] || body["messages"].find { |message| %w[system developer].include?(message["role"]) }

  def opening_of(body) = body["messages"].find { |message| !%w[system developer].include?(message["role"]) }

  def openrouter_reply(text)
    { id: "gen-#{SecureRandom.hex(4)}", object: "chat.completion", model: "anthropic/claude-haiku-5.5",
      choices: [ { index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 20, completion_tokens: 2 } }
  end

  def openrouter_tool_call(name, id: "call_1")
    { id: "gen-#{SecureRandom.hex(4)}", object: "chat.completion", model: "anthropic/claude-haiku-5.5",
      choices: [ { index: 0, message: { role: "assistant", content: "", tool_calls: [ { id: id, type: "function", function: { name: name, arguments: "{}" } } ] },
                   finish_reason: "tool_calls" } ],
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
