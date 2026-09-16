require "test_helper"

class FirefightAi::AgentLoopTest < ActiveSupport::TestCase
  # Stands in for a RubyLLM chat. A reply asking for tools is answered on the next move, as RubyLLM does.
  class FakeChat
    attr_reader :messages, :model_calls

    def initialize(replies)
      @replies = replies
      @messages = []
      @model_calls = 0
    end

    def to_llm = self

    def add_message(attributes)
      messages << RubyLLM::Message.new(**attributes)
      messages.last
    end

    def step
      pending = pending_tool_call
      return answer_tool_call(pending) if pending

      @model_calls += 1
      reply = @replies.shift
      return nil if reply.nil?

      messages << reply
      reply
    end

    private

    def pending_tool_call
      response = messages.reverse.find { |message| message.role != :system && !message.tool_result? }
      return nil unless response&.tool_call?

      answered = messages.filter_map { |message| message.tool_call_id if message.tool_result? }
      (response.tool_calls.keys - answered).first
    end

    def answer_tool_call(tool_call_id)
      messages << RubyLLM::Message.new(role: :tool, content: "ran", tool_call_id: tool_call_id)
      messages.last
    end
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @answered = false
  end

  test "the run ends as answered once the agent has concluded" do
    chat = FakeChat.new([ tool_reply("call_1"), llm_reply(content: "done") ])
    answered = -> { chat.messages.any?(&:tool_result?) }

    outcome = run_loop(chat, answered: answered)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal 1, outcome.turns_used
  end

  test "a model call is billed and running its tools is not" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 0.02), tool_reply("call_2", cost: 0.01) ])
    answered = -> { chat.messages.count(&:tool_result?) >= 2 }

    assert_difference "Inference.count", 2 do
      run_loop(chat, answered: answered)
    end

    assert_equal 2, chat.model_calls
    assert_equal [ "investigation" ], Inference.where(inferable: @incident).pluck(:feature).uniq
  end

  test "a plain reply is reminded once and ends the run the second time" do
    chat = FakeChat.new([ llm_reply(content: "I think it was the deploy"), llm_reply(content: "Still thinking") ])

    outcome = run_loop(chat)

    assert_equal FirefightAi::AgentLoop::STATUS_STALLED, outcome.status
    assert_equal [ FirefightAi::AgentLoop::REMINDER ], chat.messages.select { |m| m.role == :user }.last(1).map(&:content)
  end

  test "spending the budget buys one last turn, then the run stops" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 5.00), tool_reply("call_2"), tool_reply("call_3") ])

    outcome = run_loop(chat, budget: budget(max_spend_cents: 400))

    assert_equal FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET, outcome.status
    assert_equal 500, outcome.spent_cents
    assert_includes chat.messages.map(&:content), FirefightAi::AgentLoop::LAST_TURN
    assert_equal 2, chat.model_calls, "the last turn is one more model call, not a whole run"
  end

  test "a run that reaches the turn guard stops" do
    chat = FakeChat.new(Array.new(5) { |index| tool_reply("call_#{index}") })

    outcome = run_loop(chat, budget: budget(max_turns: 2))

    assert_equal FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS, outcome.status
    assert_equal 2, outcome.turns_used
  end

  test "a repeated tool call id stops the run rather than paying for it forever" do
    chat = FakeChat.new([ tool_reply("call_0"), tool_reply("call_0"), tool_reply("call_0") ])

    outcome = run_loop(chat)

    assert_equal FirefightAi::AgentLoop::STATUS_REPEATED_TOOL_CALL, outcome.status
    assert_equal 2, outcome.turns_used
  end

  test "each turn reports what it spent so the record survives a crash" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 0.01), tool_reply("call_2", cost: 0.02), llm_reply(content: "x") ])

    turns = []
    run_loop(chat) { |turn| turns << [ turn.turns_used, turn.spent_cents ] }

    assert_equal [ [ 1, 1 ], [ 2, 3 ] ], turns.first(2)
  end

  test "a resumed run carries the turns and spend it already used" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 0.01) ])

    outcome = run_loop(chat, budget: budget(max_turns: 10, turns_used: 4, spent_cents: 12))

    assert_equal 5, outcome.turns_used
    assert_equal 13, outcome.spent_cents
  end

  private

  def tool_reply(tool_call_id, cost: 0.0)
    llm_reply(
      content: "", cost: cost,
      tool_calls: { tool_call_id => RubyLLM::ToolCall.new(id: tool_call_id, name: "list_commits", arguments: {}) }
    )
  end

  def budget(max_spend_cents: 400, max_turns: 500, turns_used: 0, spent_cents: 0)
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: max_spend_cents, max_turns: max_turns, turns_used: turns_used, spent_cents: spent_cents
    )
  end

  def run_loop(chat, budget: budget(), answered: -> { false }, &on_turn)
    FirefightAi::AgentLoop.new(
      chat: chat, budget: budget, answered: answered,
      inference: { workspace: @workspace, feature: "investigation", provider: "openai", model: "gpt-4o", inferable: @incident }
    ).run(&on_turn)
  end
end
