require "test_helper"

class Conversation::RunnerTest < ActiveSupport::TestCase
  # Stands in for the engine, so a turn's bookkeeping is tested without calling a model.
  class FakeResponder
    attr_reader :calls
    attr_accessor :options

    def initialize(chat, outcome:, reply: nil, turns: [], steps: [])
      @chat = chat
      @outcome = outcome
      @reply = reply
      @turns = turns
      @steps = steps
      @calls = []
    end

    def run(**arguments, &on_turn)
      @calls << arguments
      @steps.each { |step| arguments[:on_step].call(step) }
      @turns.each { |turn| on_turn.call(turn) }
      @chat.call.add_message(role: :assistant, content: @reply) if @reply
      @outcome
    end

    def ai_model = FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @conversation = @workspace.conversations.create!(
      subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id,
      thread_id: "1700000000.000100", started_by: workspace_memberships(:alice_workspace_one),
      max_turns: 40, max_spend_cents: 50
    )
    stub_post_message
    stub_agent_session
  end

  test "the agent's reply is posted in the thread it was asked in" do
    fake(reply: "The 14:02 deploy raised the pool size")
    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:blocks].sole.dig(:text, :text).include?("14:02 deploy")
    end.returns({ ok: true, ts: "1" })

    Conversation::Runner.new(@conversation).run(question: "what is going on")
  end

  test "the person is told when a turn ran out of room rather than being left waiting" do
    fake(outcome: FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET)
    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:blocks].sole.dig(:text, :text).include?("could not finish")
    end.returns({ ok: true, ts: "1" })

    Conversation::Runner.new(@conversation).run(question: "what is going on")
  end

  test "each turn is written down, so a long conversation cannot spend past its ceiling" do
    fake(reply: "ok", turns: [ FirefightAi::AgentLoop::Turn.new(turns_used: 3, spent_cents: 11) ])

    Conversation::Runner.new(@conversation).run(question: "what is going on")

    @conversation.reload
    assert_equal 3, @conversation.turns_used
    assert_equal 11, @conversation.spent_cents
  end

  test "a second question carries on in the same chat" do
    fake(reply: "first")
    Conversation::Runner.new(@conversation).run(question: "one")
    chat_id = @conversation.reload.chat.id

    fake(reply: "second")
    Conversation::Runner.new(@conversation.reload).run(question: "two")

    assert_equal chat_id, @conversation.reload.chat.id
  end

  test "the agent knows which incident it is standing in" do
    responder = fake(reply: "ok")

    Conversation::Runner.new(@conversation).run(question: "what is going on")

    assert_match @incident.identifier, responder.calls.sole[:context]
    assert_equal "what is going on", responder.calls.sole[:question]
  end

  test "a tool the agent reaches for is shown as a step" do
    fake(reply: "ok", steps: [ FirefightAi::AgentLoop::Step.new(key: "call_1", tool: "search_incidents", status: :running) ])
    Slack::Client.expects(:append_stream).with do |arguments|
      arguments[:chunks].sole.dig(:task, :title) == "Search incidents"
    end.returns({ ok: true })

    Conversation::Runner.new(@conversation).run(question: "what is going on")
  end

  test "a dashboard chat posts nothing, since the page reads the chat itself" do
    personal = personal_chat
    fake(reply: "The 14:02 deploy raised the pool size")
    Slack::Client.expects(:start_stream).never
    Slack::Client.expects(:post_message).never

    Conversation::Runner.new(personal).run(question: "what changed today")

    assert_equal "The 14:02 deploy raised the pool size",
                 personal.reload.chat.messages.where(role: "assistant").sole.content
  end

  test "a dashboard answer is asked for without Slack markup, because the page shows it as written" do
    personal = personal_chat
    responder = fake(reply: "ok")

    Conversation::Runner.new(personal).run(question: "what changed today")

    assert_equal Conversation::Runner::PLAIN_OUTPUT_STYLE, responder.options[:output_style]
  end

  test "a reply Slack refuses is logged rather than paid for twice" do
    fake(reply: "ok")
    Slack::Client.stubs(:stop_stream).raises(AdapterError, "channel_not_found")

    assert_nothing_raised { Conversation::Runner.new(@conversation).run(question: "what is going on") }
  end

  private

  # The fake reads the chat off @conversation, so a dashboard chat takes that place for the turn.
  def personal_chat
    @conversation = Conversation.start_personal!(
      workspace: @workspace, member: workspace_memberships(:alice_workspace_one)
    )
  end

  def fake(outcome: FirefightAi::AgentLoop::STATUS_ANSWERED, reply: nil, turns: [], steps: [])
    responder = FakeResponder.new(
      -> { @conversation.reload.chat },
      outcome: FirefightAi::AgentLoop::Outcome.new(status: outcome, turns_used: turns.size, spent_cents: 0),
      reply: reply, turns: turns, steps: steps
    )
    FirefightAi::Responder.stubs(:new).with { |*, **options| responder.options = options }.returns(responder)
    responder
  end
end
