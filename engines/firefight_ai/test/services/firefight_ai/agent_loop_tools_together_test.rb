require "test_helper"
require "opentelemetry/sdk"

# The reads of one model step run together, and everything else one at a time as before. Every result is saved, and
# every step reported, in the order the model asked.
class FirefightAi::AgentLoopToolsTogetherTest < ActiveSupport::TestCase
  include FakeProviderHelper

  WAIT = 5

  # A read that waits until the step's other reads have started, so it only answers when they run at once, and answers
  # after the reads asked after it, so saving in the order they answered would put it last.
  class Read < RubyLLM::Tool
    def initialize(name, started:, finish_after: nil, log: nil)
      super()
      @name = name
      @started = started
      @finish_after = finish_after
      @log = log
    end

    attr_reader :name

    def description = "Reads #{@name}"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def concurrent_read? = true

    def call(tool_call: nil, **)
      @log&.push([ :started, @name ])
      @started.count_down
      raise "#{@name} never ran beside the others" unless @started.wait(WAIT)
      raise "#{@finish_after.name} never answered" if @finish_after && !@finish_after.answered.wait(WAIT)

      "#{@name} read"
    ensure
      answered.set
    end

    def answered = (@answered ||= Concurrent::Event.new)
  end

  # A change. It runs alone, so it sees every read asked before it saved, and none asked after it started.
  class Change < RubyLLM::Tool
    def initialize(chat, log)
      super()
      @chat = chat
      @log = log
    end

    def name = "restart"

    def description = "Restarts something"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def call(tool_call: nil, **)
      saved = Chat::Message.where(chat_id: @chat.id, role: "tool").count
      @log.push([ :changed, saved ])
      "restarted"
    end
  end

  # A read that still needs the person, so it is asked about and never run beside the others.
  class AskedRead < Read
    def requires_approval? = true
  end

  # A read that counts how many of its calls run at once.
  class Counted < RubyLLM::Tool
    def initialize
      super()
      @running = Concurrent::AtomicFixnum.new
      @most = Concurrent::AtomicFixnum.new
    end

    def name = "count"

    def description = "Counts"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def concurrent_read? = true

    def most = @most.value

    def call(tool_call: nil, **)
      now = @running.increment
      @most.update { |most| [ most, now ].max }
      Thread.pass
      "counted"
    ensure
      @running.decrement
    end
  end

  setup do
    FakeProviderHelper::Adapter.reset!
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @choice = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: "sk-ant-test"))
    @chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: @choice)
    @steps = []
  end

  test "reads asked together run at once, and their results and steps come in the order asked" do
    started = Concurrent::CountDownLatch.new(3)
    third = Read.new("third", started: started)
    second = Read.new("second", started: started, finish_after: third)
    first = Read.new("first", started: started, finish_after: second)
    ready([ first, second, third ])
    ask_for_tools("first", "second", "third")

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, run_loop.status
    assert_equal [ "toolu_first", "toolu_second", "toolu_third" ], saved_results.map(&:tool_call_id)
    assert_equal [ "first read", "second read", "third read" ], saved_results.map(&:content)
    running, done = @steps.partition { |step| step.status == FirefightAi::AgentLoop::STEP_RUNNING }
    assert_equal [ "toolu_first", "toolu_second", "toolu_third" ], running.map(&:key)
    assert_equal [ "toolu_first", "toolu_second", "toolu_third" ], done.map(&:key)
  end

  test "a run nobody can stop, whose tools run on its own thread, runs its reads together too" do
    started = Concurrent::CountDownLatch.new(2)
    second = Read.new("second", started: started)
    ready([ Read.new("first", started: started, finish_after: second), second ])
    ask_for_tools("first", "second")

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, run_loop(canceled: FirefightAi::AgentLoop::NEVER_CANCELED).status
    assert_equal [ "toolu_first", "toolu_second" ], saved_results.map(&:tool_call_id)
  end

  test "a change waits for the reads asked before it, and the reads after it wait for the change" do
    log = Concurrent::Array.new
    before = Concurrent::CountDownLatch.new(2)
    after = Concurrent::CountDownLatch.new(2)
    ready([ Read.new("first", started: before, log: log), Read.new("second", started: before, log: log), Change.new(@chat, log),
            Read.new("third", started: after, log: log), Read.new("fourth", started: after, log: log) ])
    ask_for_tools("first", "second", "restart", "third", "fourth")

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, run_loop.status
    change = log.index([ :changed, 2 ])
    assert change, "the change saw both reads asked before it saved: #{log.inspect}"
    assert_equal [ [ :started, "third" ], [ :started, "fourth" ] ].to_set, log[(change + 1)..].to_set
    assert_equal %w[toolu_first toolu_second toolu_restart toolu_third toolu_fourth], saved_results.map(&:tool_call_id)
  end

  test "a read that needs the person is asked about and does not run, as before" do
    log = Concurrent::Array.new
    started = Concurrent::CountDownLatch.new(1)
    ready([ Read.new("first", started: started, log: log), AskedRead.new("second", started: Concurrent::CountDownLatch.new(1), log: log) ])
    ask_for_tools("first", "second")

    assert_equal FirefightAi::AgentLoop::STATUS_WAITING, run_loop.status
    assert_equal [ [ :started, "first" ] ], log.to_a
    assert_equal [ "toolu_first" ], saved_results.map(&:tool_call_id)
    assert @chat.to_llm.awaiting_approval?
  end

  test "two calls of the same tool never run at once" do
    counted = Counted.new
    ready([ counted ])
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_a", name: "count", input: {} }, { type: "tool_use", id: "toolu_b", name: "count", input: {} } ],
                  usage: { input_tokens: 5, output_tokens: 5 } })
    answer_done

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, run_loop.status
    assert_equal 1, counted.most
    assert_equal %w[toolu_a toolu_b], saved_results.map(&:tool_call_id)
  end

  test "each tool call is a span named for the tool, under the trace that ran the step" do
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))
    before = OpenTelemetry.tracer_provider
    OpenTelemetry.tracer_provider = provider
    started = Concurrent::CountDownLatch.new(2)
    ready([ Read.new("first", started: started), Read.new("second", started: started) ])
    ask_for_tools("first", "second")

    provider.tracer("test").in_span("reply") { run_loop(canceled: -> { false }) }

    spans = exporter.finished_spans
    reply = spans.find { |span| span.name == "reply" }
    tools = spans.select { |span| span.name.start_with?("execute_tool") }
    assert_equal [ "execute_tool first", "execute_tool second" ], tools.map(&:name).sort
    assert_equal [ [ "first", "toolu_first" ], [ "second", "toolu_second" ] ],
                 tools.map { |span| span.attributes.values_at("gen_ai.tool.name", "gen_ai.tool.call.id") }.sort
    assert(tools.all? { |span| span.trace_id == reply.trace_id && span.parent_span_id == reply.span_id })
  ensure
    provider&.shutdown
    OpenTelemetry.tracer_provider = before if before
  end

  private

  def ready(tools)
    FirefightAi.ready_chat(@chat, choice: @choice, instructions: "Read.", tools: tools)
    @chat.add_message(role: :user, content: "Look")
  end

  def ask_for_tools(*names)
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: names.map { |name| { type: "tool_use", id: "toolu_#{name}", name: name, input: {} } },
                  usage: { input_tokens: 5, output_tokens: 5 } })
    answer_done
  end

  def answer_done
    answer_with({ id: "msg_2", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "end_turn",
                  content: [ { type: "text", text: "Done." } ], usage: { input_tokens: 9, output_tokens: 2 } })
  end

  # Stoppable unless told otherwise, as a chat turn is, so the tools run beside the loop.
  def run_loop(canceled: -> { false })
    FirefightAi::AgentLoop.new(
      chat: @chat, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5), answered: -> { false }, reply_is_answer: true,
      inference: { workspace: @workspace, feature: "tools_together_test", provider: "anthropic", model: "claude-haiku-4-5" }, choice: @choice,
      canceled: canceled, on_step: ->(step) { @steps << step }
    ).run
  end

  def saved_results = Chat::Message.where(chat_id: @chat.id, role: "tool").order(:created_at, :id).map(&:to_llm)
end
