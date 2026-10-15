require "test_helper"

# The reads of one model step run together (FirefightAi::AgentLoop::ToolsTogether), and the rows they write while they
# run keep the order the model asked for them, however long each call takes.
class CallOrderTest < ActiveSupport::TestCase
  include FakeProviderHelper

  CREATE_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
  WAIT = 5
  # Long enough that the later call writes first unless it waits for the earlier one.
  SLOW = 0.3

  # A read that numbers an investigation step as it starts, then keeps a chart and a saved result as it ends. The slow
  # one waits until the quick one has started, then takes its time.
  class Writer < RubyLLM::Tool
    def initialize(name, investigation:, chat:, started:, slow:)
      super()
      @name = name
      @investigation = investigation
      @chat = chat
      @started = started
      @slow = slow
    end

    attr_reader :name

    def description = "Reads #{@name}"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def concurrent_read? = true

    def call(tool_call: nil, **)
      if @slow
        raise "the quick call never started" unless @started.wait(WAIT)

        sleep SLOW
      else
        @started.count_down
      end
      Investigation::ToolCall.run!(@investigation, action_key: CREATE_KEY, tool_name: @name, label: @name) { "#{@name} read" }
      now = Time.current
      Chat::Chart.record!(@chat, tool_call.id, [ { "title" => @name, "from" => (now - 1.hour).iso8601, "to" => now.iso8601, "series" => [] } ])
      @chat.saved_results.keep!(tool_name: @name, text: "#{@name} read")
      "#{@name} read"
    end
  end

  setup do
    FakeProviderHelper::Adapter.reset!
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      triggered_by: workspace_memberships(:alice_workspace_one), max_turns: 10, max_spend_cents: 400
    )
    Ability::Grant.create!(workspace: @workspace, principal: SystemAgent.investigator, action: Ability::Action.system!(CREATE_KEY))
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @choice = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: "sk-ant-test"))
    @chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: @choice)
  end

  test "an earlier call that answers last still writes its step, its chart and its saved result first" do
    started = Concurrent::CountDownLatch.new(1)
    tools = [ Writer.new("slow", investigation: @investigation, chat: @chat, started: started, slow: true),
              Writer.new("quick", investigation: @investigation, chat: @chat, started: started, slow: false) ]
    FirefightAi.ready_chat(@chat, choice: @choice, instructions: "Read.", tools: tools)
    @chat.add_message(role: :user, content: "Look")
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_slow", name: "slow", input: {} }, { type: "tool_use", id: "toolu_quick", name: "quick", input: {} } ],
                  usage: { input_tokens: 5, output_tokens: 5 } })
    answer_with({ id: "msg_2", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "end_turn",
                  content: [ { type: "text", text: "Done." } ], usage: { input_tokens: 9, output_tokens: 2 } })

    outcome = FirefightAi::AgentLoop.new(
      chat: @chat, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5), answered: -> { false }, reply_is_answer: true,
      inference: { workspace: @workspace, feature: "call_order_test", provider: "anthropic", model: "claude-haiku-4-5" }, choice: @choice,
      canceled: -> { false }
    ).run

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ [ 1, "slow" ], [ 2, "quick" ] ], @investigation.steps.order(:position).pluck(:position, :tool_name)
    assert_equal %w[slow quick], @chat.charts.in_order.pluck(:title)
    assert_equal [ [ "result_1", "slow" ], [ "result_2", "quick" ] ], @chat.saved_results.in_order.pluck(:handle, :tool_name)
  end

  test "a call not running beside others writes at once" do
    assert_equal :written, CallOrder.in_turn(:anything) { :written }
    assert_equal :written, CallOrder.after_earlier_calls { :written }
  end

  test "a later call waits for each earlier one to write first or to end, and never the other way round" do
    group = CallOrder::Group.new(3)
    written = Concurrent::Array.new
    later = Thread.new { CallOrder.running(group, 2) { CallOrder.after_earlier_calls { written << :third } } }
    middle = Thread.new { CallOrder.running(group, 1) { CallOrder.in_turn(:step) { written << :second } } }
    sleep 0.05
    assert_empty written
    CallOrder.running(group, 0) { CallOrder.in_turn(:step) { written << :first } }

    [ later, middle ].each { |thread| thread.join(WAIT) }
    assert_equal %i[first second third], written.to_a
  end
end
