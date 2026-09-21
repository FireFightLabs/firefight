require "test_helper"

# How the loop makes room when the model's window fills. The chat's own records do the work,
# the loop only decides when.
class FirefightAi::AgentLoopMemoryTest < ActiveSupport::TestCase
  # Stands in for a saved chat that can make room.
  class FakeMemory
    attr_reader :cleared_at, :rebuilt_with

    def initialize(window:, frees: 0)
      @window = window
      @frees = frees
      @cleared_at = []
      @rebuilt_with = []
    end

    def context_window! = @window

    def clear_old_results!(tokens_before:)
      @cleared_at << tokens_before
      @frees
    end

    def rebuild!(note:, tokens_before:)
      @rebuilt_with << note
    end
  end

  class FakeChat
    attr_reader :messages, :tool_choices

    def initialize(replies)
      @replies = replies
      @messages = []
      @tool_choices = []
    end

    def to_llm = self
    def reload = self
    def awaiting_approval? = false
    def before_tool_call(&) = nil
    def after_message(&) = nil

    def with_tool_options(choice:)
      @tool_choices << choice
      self
    end

    def add_message(attributes)
      messages << RubyLLM::Message.new(**attributes)
      messages.last
    end

    def step(&)
      reply = @replies.shift
      raise reply if reply.is_a?(Exception)

      messages << reply if reply
      reply
    end
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a chat with room to spare is left alone" do
    memory = FakeMemory.new(window: 100_000)

    run_loop(FakeChat.new([ reply("the answer", read: 10_000) ]), memory: memory)

    assert_empty memory.cleared_at
    assert_empty memory.rebuilt_with
  end

  test "past half the window, old tool results are cleared before the next turn" do
    memory = FakeMemory.new(window: 100_000, frees: 30_000)
    chat = FakeChat.new([ reply("thinking", read: 55_000), reply("the answer", read: 26_000) ])

    run_loop(chat, memory: memory, reply_is_answer: false, answered: -> { chat.messages.size > 2 })

    assert_equal 1, memory.cleared_at.size
    assert_operator memory.cleared_at.sole, :>=, 55_000
    assert_empty memory.rebuilt_with, "clearing freed enough, so the chat is not rebuilt"
  end

  test "when clearing does not free enough, the agent writes itself a note and the chat is rebuilt" do
    memory = FakeMemory.new(window: 100_000, frees: 0)
    chat = FakeChat.new([ reply("thinking", read: 80_000), reply("The deploy looks guilty. Next, the pool config.", read: 81_000), reply("the answer", read: 9_000) ])

    run_loop(chat, memory: memory, reply_is_answer: false, answered: -> { chat.messages.count { |message| message.role == :assistant } >= 3 })

    assert_equal [ "The deploy looks guilty. Next, the pool config." ], memory.rebuilt_with
    assert_equal [ :none, nil ], chat.tool_choices, "the note is written without tools, and tools come back afterwards"
  end

  test "the note is a model call like any other, so it is billed" do
    memory = FakeMemory.new(window: 100_000, frees: 0)
    chat = FakeChat.new([ reply("thinking", read: 80_000), reply("note", read: 81_000, cost: 0.03), reply("the answer", read: 9_000) ])

    outcome = run_loop(chat, memory: memory, reply_is_answer: false, answered: -> { chat.messages.count { |message| message.role == :assistant } >= 3 })

    assert_equal 30_000, outcome.spent_micros
  end

  test "tool results that arrived since the last reply count, since the provider has not seen them yet" do
    memory = FakeMemory.new(window: 100_000, frees: 50_000)
    chat = FakeChat.new([ reply("thinking", read: 30_000), reply("the answer", read: 40_000) ])
    chat.define_singleton_method(:step) do |&block|
      reply = super(&block)
      messages << RubyLLM::Message.new(role: :tool, content: "x" * 120_000, tool_call_id: "call_1") if messages.count { |message| message.role == :assistant } == 1
      reply
    end

    run_loop(chat, memory: memory, reply_is_answer: false, answered: -> { chat.messages.count { |message| message.role == :assistant } >= 2 })

    assert_equal 1, memory.cleared_at.size, "30,000 read plus 30,000 waiting is past half of 100,000"
  end

  test "a provider that still says too long gets the chat rebuilt and one more try" do
    memory = FakeMemory.new(window: 100_000)
    chat = FakeChat.new([ RubyLLM::ContextLengthExceededError.new("too long"), reply("the answer", read: 9_000) ])

    outcome = run_loop(chat, memory: memory)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ nil ], memory.rebuilt_with, "the model cannot be asked for a note when it cannot be called at all"
  end

  test "too long a second time is the end, since making room did not help" do
    memory = FakeMemory.new(window: 100_000)
    chat = FakeChat.new([ RubyLLM::ContextLengthExceededError.new("too long"), RubyLLM::ContextLengthExceededError.new("too long") ])

    assert_raises(RubyLLM::ContextLengthExceededError) { run_loop(chat, memory: memory) }
  end

  test "a loop given no memory behaves as it always did" do
    outcome = run_loop(FakeChat.new([ reply("the answer", read: 99_000) ]), memory: nil)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
  end

  private

  def reply(content, read:, cost: 0.0)
    message = RubyLLM::Message.new(role: :assistant, content: content, input_tokens: read, output_tokens: 0)
    message.stubs(:cost).returns(stub(total: cost))
    message
  end

  def run_loop(chat, memory:, reply_is_answer: true, answered: -> { false })
    FirefightAi::AgentLoop.new(
      chat: chat, memory: memory, answered: answered, reply_is_answer: reply_is_answer,
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 50),
      inference: { workspace: @workspace, feature: "investigation", provider: "openai", model: "gpt-4o", inferable: @incident }
    ).run
  end
end
