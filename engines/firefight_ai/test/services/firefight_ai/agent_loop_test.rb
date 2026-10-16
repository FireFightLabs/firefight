require "test_helper"

class FirefightAi::AgentLoopTest < ActiveSupport::TestCase
  # Stands in for a RubyLLM chat. A reply asking for tools is answered on the next move, as RubyLLM does.
  class FakeChat
    attr_reader :messages, :model_calls, :streamed

    def initialize(replies)
      @replies = replies
      @messages = []
      @model_calls = 0
    end

    def to_llm = self

    def caching = nil

    def with_tool_options(**) = self

    def awaiting_approval? = @awaiting_approval || false

    def wait_for_approval! = (@awaiting_approval = true)

    def before_tool_call(&block) = (@before_tool_call = block)

    # RubyLLM hands this one the tool's own return value, not a message.
    def after_tool_result(&block) = (@after_tool_result = block)

    def after_message(&block) = (@after_message = block)

    def add_message(attributes)
      messages << RubyLLM::Message.new(**attributes)
      messages.last
    end

    def step(&on_chunk)
      pending = pending_tool_call
      return answer_tool_call(pending) if pending

      @model_calls += 1
      reply = @replies.shift
      return nil if reply.nil?
      raise reply if reply.is_a?(Exception)

      @streamed = on_chunk ? true : @streamed
      stream(reply, &on_chunk) if on_chunk
      messages << reply
      reply
    end

    # RubyLLM yields a chunk per piece of the reply, each one a message carrying only that piece.
    def stream(reply)
      reply.content.to_s.chars.each_slice(4) do |piece|
        yield RubyLLM::Message.new(role: :assistant, content: piece.join)
      end
    end

    private

    def pending_tool_call
      response = messages.reverse.find { |message| message.role != :system && !message.tool_result? }
      return nil unless response&.tool_call?

      answered = messages.filter_map { |message| message.tool_call_id if message.tool_result? }
      (response.tool_calls.keys - answered).first
    end

    def answer_tool_call(tool_call_id)
      call = messages.reverse.find(&:tool_call?).tool_calls[tool_call_id]
      @before_tool_call&.call(call)
      result = "ran"
      @after_tool_result&.call(result)
      messages << RubyLLM::Message.new(role: :tool, content: result, tool_call_id: tool_call_id)
      @after_message&.call(messages.last)
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

  test "the loop's own nudges go through the caller, so the app can tell them from what a person said" do
    chat = FakeChat.new([ llm_reply(content: "I think it was the deploy"), llm_reply(content: "Still thinking") ])
    nudges = []

    run_loop(chat, nudge: ->(text) { nudges << text })

    assert_equal [ FirefightAi::AgentLoop::REMINDER ], nudges
  end

  test "spending the budget buys one last turn, then the run stops" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 5.00), tool_reply("call_2"), tool_reply("call_3") ])

    outcome = run_loop(chat, budget: budget(max_spend_cents: 400))

    assert_equal FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET, outcome.status
    assert_equal 5_000_000, outcome.spent_micros
    assert_includes chat.messages.map(&:content), FirefightAi::AgentLoop::LAST_TURN
    assert_equal 2, chat.model_calls, "the last turn is one more model call, not a whole run"
  end

  test "what helpers spend beside the loop counts against its budget, and the caller hears it before the next turn" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 0.01), tool_reply("call_2"), tool_reply("call_3") ])
    purse = FirefightAi::AgentLoop::Purse.new
    turns = []
    helpers_spend = ->(step) { purse.add(4_000_000) if step.status == FirefightAi::AgentLoop::STEP_RUNNING && step.key == "call_1" }

    outcome = run_loop(chat, budget: budget(max_spend_cents: 400), on_step: helpers_spend, purse: purse) { |turn| turns << turn.spent_micros }

    assert_equal FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET, outcome.status
    assert_equal [ 10_000, 4_010_000 ], turns.first(2), "the helpers' spend is reported once the tool answers, before the next model call"
    assert_equal 4_010_000, outcome.spent_micros
    assert_equal 2, chat.model_calls
  end

  test "a purse is shared safely between threads" do
    purse = FirefightAi::AgentLoop::Purse.new(100)

    Array.new(8) { Thread.new { 1_000.times { purse.add(1) } } }.each(&:join)

    assert_equal 8_100, purse.spent
    assert_equal (400 * FirefightAi::AgentLoop::MICROS_PER_CENT) - 8_100, purse.left(400)
  end

  # Seen in a real chat. OpenAI refuses a chat with a message between a tool call and its result, so the run died.
  test "the last turn waits for the tools already asked for, so nothing sits between a call and its result" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 5.00), llm_reply(content: "It was the database") ])

    outcome = run_loop(chat, budget: budget(max_spend_cents: 400), reply_is_answer: true)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    contents = chat.messages.map(&:content)
    assert_operator chat.messages.index(&:tool_result?), :<, contents.index(FirefightAi::AgentLoop::LAST_TURN)
  end

  test "a tool asked for on the last turn still gets its result, so the saved chat can be sent again" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 5.00), tool_reply("call_2") ])

    outcome = run_loop(chat, budget: budget(max_spend_cents: 400))

    assert_equal FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET, outcome.status
    assert_equal [ "call_1", "call_2" ], chat.messages.select(&:tool_result?).map(&:tool_call_id)
  end

  test "a run stopped by the turn guard still saves the result of the tool it last asked for" do
    chat = FakeChat.new(Array.new(5) { |index| tool_reply("call_#{index}") })

    run_loop(chat, budget: budget(max_turns: 2))

    assert_equal [ "call_0", "call_1" ], chat.messages.select(&:tool_result?).map(&:tool_call_id)
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
    run_loop(chat) { |turn| turns << [ turn.turns_used, turn.spent_micros ] }

    assert_equal [ [ 1, 10_000 ], [ 2, 30_000 ] ], turns.first(2)
  end

  test "small replies add up to what they cost, not a cent each" do
    chat = FakeChat.new(Array.new(10) { |index| tool_reply("call_#{index}", cost: 0.003) } + [ llm_reply(content: "x") ])

    outcome = run_loop(chat)

    assert_equal 30_000, outcome.spent_micros
  end

  test "each tool the agent reaches for is reported as it runs and when it answers" do
    chat = FakeChat.new([ tool_reply("call_1"), llm_reply(content: "done") ])
    steps = []

    run_loop(chat, on_step: ->(step) { steps << [ step.key, step.tool, step.status ] })

    assert_equal [ [ "call_1", "list_commits", :running ], [ "call_1", nil, :done ] ], steps
  end

  test "in a conversation the reply is the answer, so the turn ends there" do
    chat = FakeChat.new([ llm_reply(content: "It was the 14:02 deploy") ])

    outcome = run_loop(chat, reply_is_answer: true)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal 1, outcome.turns_used
  end

  test "a reply is handed over as it is written when someone is watching" do
    chat = FakeChat.new([ llm_reply(content: "It was the 14:02 deploy") ])
    pieces = []

    run_loop(chat, reply_is_answer: true, on_chunk: ->(text) { pieces << text })

    assert_operator pieces.size, :>, 1
    assert_equal "It was the 14:02 deploy", pieces.join
  end

  test "a turn nobody is watching is not streamed" do
    chat = FakeChat.new([ llm_reply(content: "done") ])

    run_loop(chat, reply_is_answer: true)

    assert_nil chat.streamed
  end

  test "an answer goes out as it is written, streamed, with nothing asked of it after" do
    chat = FakeChat.new([ tool_reply("call_1"), llm_reply(content: "INC-4 is resolved") ])
    pieces = []
    nudges = []

    outcome = run_loop(chat, reply_is_answer: true, on_chunk: ->(text) { pieces << text }, nudge: ->(text) { nudges << text })

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal "INC-4 is resolved", pieces.join
    assert_empty nudges
  end

  test "a tool call waiting on a person stops the turn without calling the model again" do
    chat = FakeChat.new([ llm_reply(content: "never asked for") ])
    chat.wait_for_approval!

    outcome = run_loop(chat, reply_is_answer: true)

    assert_equal FirefightAi::AgentLoop::STATUS_WAITING, outcome.status
    assert_equal 0, chat.model_calls
  end

  test "a streamed turn is still billed" do
    chat = FakeChat.new([ llm_reply(content: "done", cost: 0.02) ])

    assert_difference "Inference.count", 1 do
      outcome = run_loop(chat, reply_is_answer: true, on_chunk: ->(_text) { })
      assert_equal 20_000, outcome.spent_micros
    end
  end

  test "a resumed run carries the turns and spend it already used" do
    chat = FakeChat.new([ tool_reply("call_1", cost: 0.01) ])

    outcome = run_loop(chat, budget: budget(max_turns: 10, turns_used: 4, spent_micros: 123_456))

    assert_equal 5, outcome.turns_used
    assert_equal 133_456, outcome.spent_micros
  end

  test "a message sent while the agent works joins after the tool's result, before the next model call" do
    chat = FakeChat.new([ tool_reply("call_1"), llm_reply(content: "Checked the metrics instead") ])
    sent = [ nil, "skip GitHub, look at metrics" ]
    take = -> { sent.shift&.then { |text| chat.add_message(role: :user, content: text) }.present? }

    run_loop(chat, reply_is_answer: true, take_messages: take)

    roles = chat.messages.map { |message| [ message.role, message.content ] }
    assert_equal [ :assistant, :tool, :user, :assistant ], roles.map(&:first)
    assert_equal "skip GitHub, look at metrics", roles[2].last
  end

  test "a message sent after a reply that did nothing gives the agent another chance rather than ending the run" do
    chat = FakeChat.new([ llm_reply(content: "I think it was the deploy"), llm_reply(content: "Reading it"), tool_reply("call_1") ])
    sent = [ nil, "look at the 14:02 deploy" ]
    take = -> { sent.shift&.then { |text| chat.add_message(role: :user, content: text) }.present? }
    answered = -> { chat.messages.any?(&:tool_result?) }

    outcome = run_loop(chat, answered: answered, take_messages: take)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
  end

  # Seen live: DeepSeek V4 Pro on OpenRouter sent a tool call whose arguments were not JSON, and the chat's turn failed.
  test "a chat's reply whose tool call cannot be read is asked for once more on the same model" do
    chat = FakeChat.new([ malformed, llm_reply(content: "Stopped the watch.") ])

    outcome = run_loop(chat, reply_is_answer: true, retry_malformed: true)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal 2, chat.model_calls
    assert_equal %w[error success], Inference.where(inferable: @incident).order(:created_at).pluck(:status)
    assert_equal [ "gpt-4o" ], Inference.where(inferable: @incident).pluck(:model).uniq
  end

  # Seen live: a specialist on Haiku wrote its report into one tool call, ran past its output limit halfway through, and
  # the whole check failed with "It could not run". Asked again with no word, a model writes the same long reply again.
  test "a reply cut off at the output limit mid tool call is asked for once more, told to write it shorter" do
    chat = FakeChat.new([ RubyLLM::ToolCallParseError.new(finish_reason: :max_tokens), llm_reply(content: "Reported.") ])
    said = []

    outcome = run_loop(chat, reply_is_answer: true, retry_malformed: true, nudge: ->(text) { said << text })

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal 2, chat.model_calls
    assert_equal [ FirefightAi::AgentLoop::CUT_OFF ], said
  end

  test "a reply that cannot be read for another reason is asked for again with no word added" do
    chat = FakeChat.new([ malformed, llm_reply(content: "Stopped the watch.") ])
    said = []

    run_loop(chat, reply_is_answer: true, retry_malformed: true, nudge: ->(text) { said << text })

    assert_empty said
  end

  test "a second reply that cannot be read ends the run, never a third try" do
    chat = FakeChat.new([ malformed, malformed, llm_reply(content: "never asked") ])

    assert_raises(RubyLLM::ToolCallParseError) { run_loop(chat, reply_is_answer: true, retry_malformed: true) }
    assert_equal 2, chat.model_calls
  end

  test "a loop not told to ask again fails on the first reply that cannot be read, as before" do
    chat = FakeChat.new([ malformed, llm_reply(content: "never asked") ])

    assert_raises(RubyLLM::ToolCallParseError) { run_loop(chat) }
    assert_equal 1, chat.model_calls
  end

  # Seen live: a check from outside waited on its sandbox for minutes after Stop, and the page said Stopping all along.
  test "a stop while a tool runs ends the run at once, whatever the tool waits on, and saves no result for it" do
    chat = SlowToolChat.new([ tool_reply("call_1"), llm_reply(content: "never asked") ], waits: 5)
    stop_at = clock + 0.3
    started = clock

    outcome = run_loop(chat, canceled: -> { clock > stop_at })

    assert_equal FirefightAi::AgentLoop::STATUS_CANCELED, outcome.status
    assert_operator clock - started, :<, 2.5
    assert chat.cancelled, "the chat is told, so the tool's result is never saved once it answers"
    assert_empty chat.messages.select(&:tool_result?)
    assert_equal 1, chat.model_calls
  end

  test "a tool that waits on something it can stop hears the stop and gives up" do
    chat = SlowToolChat.new([ tool_reply("call_1") ], waits: 5, stoppable: true)
    stop_at = clock + 0.3

    run_loop(chat, canceled: -> { clock > stop_at })

    assert chat.heard_stop.wait(2), "the tool's wait heard the stop"
  end

  test "a tool that finishes before any stop answers as before" do
    chat = SlowToolChat.new([ tool_reply("call_1"), llm_reply(content: "done") ], waits: 0.1)

    outcome = run_loop(chat, reply_is_answer: true, canceled: -> { false })

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ "call_1" ], chat.messages.select(&:tool_result?).map(&:tool_call_id)
  end

  private

  # A tool that takes waits seconds, waiting as a stoppable wait does when stoppable, or ignoring any stop otherwise, and
  # whose result RubyLLM drops once the chat was cancelled, as RubyLLM checks after every tool.
  class SlowToolChat < FakeChat
    attr_reader :cancelled, :heard_stop

    def initialize(replies, waits:, stoppable: false)
      super(replies)
      @waits = waits
      @stoppable = stoppable
      @heard_stop = Concurrent::Event.new
    end

    def cancel = (@cancelled = true)

    private

    def answer_tool_call(tool_call_id)
      wait
      raise RubyLLM::CancelledError if @cancelled

      super
    end

    def wait
      return sleep(@waits) unless @stoppable

      StopSignal.pause(@waits)
    rescue StopSignal::Stopped
      @heard_stop.set
      raise
    end
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def malformed = RubyLLM::ToolCallParseError.new(finish_reason: :tool_calls)

  def tool_reply(tool_call_id, cost: 0.0)
    llm_reply(
      content: "", cost: cost,
      tool_calls: { tool_call_id => RubyLLM::ToolCall.new(id: tool_call_id, name: "list_commits", arguments: {}) }
    )
  end

  def budget(max_spend_cents: 400, max_turns: 500, turns_used: 0, spent_micros: 0)
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: max_spend_cents, max_turns: max_turns, turns_used: turns_used, spent_micros: spent_micros
    )
  end

  def run_loop(chat, budget: budget(), answered: -> { false }, on_step: nil, on_chunk: nil, reply_is_answer: false,
               nudge: nil, take_messages: nil, purse: nil, retry_malformed: false, canceled: FirefightAi::AgentLoop::NEVER_CANCELED, &on_turn)
    FirefightAi::AgentLoop.new(
      chat: chat, budget: budget, answered: answered, on_step: on_step, on_chunk: on_chunk, canceled: canceled,
      reply_is_answer: reply_is_answer, nudge: nudge, take_messages: take_messages, purse: purse, retry_malformed: retry_malformed,
      inference: { workspace: @workspace, feature: "investigation", provider: "openai", model: "gpt-4o", inferable: @incident }
    ).run(&on_turn)
  end
end
