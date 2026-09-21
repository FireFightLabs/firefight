require "test_helper"

class Conversation::RunnerTest < ActiveSupport::TestCase
  # Stands in for the engine, so a turn's bookkeeping is tested without calling a model.
  class FakeResponder
    attr_reader :calls
    attr_accessor :options

    def initialize(chat, outcome:, reply: nil, turns: [], steps: [], pieces: [])
      @chat = chat
      @outcome = outcome
      @reply = reply
      @turns = turns
      @steps = steps
      @pieces = pieces
      @calls = []
    end

    def run(**arguments, &on_turn)
      @calls << arguments
      @steps.each { |step| arguments[:on_step].call(step) }
      @pieces.each { |piece| arguments[:on_chunk].call(piece) }
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

    ask(@conversation, "what is going on")
  end

  test "the person is told when a turn ran out of room rather than being left waiting" do
    fake(outcome: FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET)
    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:blocks].sole.dig(:text, :text).include?("could not finish")
    end.returns({ ok: true, ts: "1" })

    ask(@conversation, "what is going on")
  end

  test "a question starts with its own budget, whatever the questions before it spent" do
    @conversation.update!(turns_used: 39, spent_micros: 490_000)
    responder = fake(reply: "ok")

    ask(@conversation, "what is going on")

    budget = responder.calls.sole[:budget]
    assert_equal 0, budget.turns_used
    assert_equal 0, budget.spent_micros
    assert_equal 50, budget.max_spend_cents
  end

  test "what each question spent adds up on the conversation" do
    @conversation.update!(turns_used: 4, spent_micros: 200_000)
    fake(reply: "ok", turns: [
      FirefightAi::AgentLoop::Turn.new(turns_used: 1, spent_micros: 40_000),
      FirefightAi::AgentLoop::Turn.new(turns_used: 3, spent_micros: 110_000)
    ])

    ask(@conversation, "what is going on")

    @conversation.reload
    assert_equal 7, @conversation.turns_used
    assert_equal 310_000, @conversation.spent_micros
  end

  test "the agent's own nudges are saved as nudges" do
    responder = fake(reply: "ok")

    ask(@conversation, "what is going on")
    responder.calls.sole[:nudge].call(FirefightAi::AgentLoop::LAST_TURN)

    assert_equal [ "what is going on", "ok" ], @conversation.reload.chat.readable_messages.map(&:content)
  end

  test "a second question carries on in the same chat" do
    fake(reply: "first")
    ask(@conversation, "one")
    chat_id = @conversation.reload.chat.id

    fake(reply: "second")
    ask(@conversation.reload, "two")

    assert_equal chat_id, @conversation.reload.chat.id
  end

  test "a second question is handed the tools the first one found, so it does not search for them again" do
    # Offering to the live chat needs a provider, which the suite does not have.
    Chat.any_instance.stubs(:with_tools)
    first = fake(reply: "first")
    ask(@conversation, "what incidents mention checkout?")
    first.calls.sole[:tools].first.execute(query: "search incidents")

    second = fake(reply: "second")
    ask(@conversation.reload, "and last week?")

    assert_includes second.calls.sole[:tools].map(&:name), Mcp::Tools::SEARCH_INCIDENTS
  end

  test "the agent knows which incident it is standing in" do
    responder = fake(reply: "ok")

    ask(@conversation, "what is going on")

    assert_match @incident.identifier, responder.calls.sole[:context]
  end

  test "the agent is told who it acts for and their role, so it can say what they may do" do
    responder = fake(reply: "ok")

    ask(@conversation, "am I an admin")

    context = responder.calls.sole[:context]
    assert_match @conversation.started_by.display_name, context
    assert_match "role in this workspace is #{@conversation.started_by.role}", context
  end

  test "the question is written down before the model is asked, so the person sees their own words" do
    fake(reply: "ok")

    ask(@conversation, "what is going on")

    assert_equal "what is going on",
                 @conversation.reload.chat.messages.where(role: Chat::Message::ROLE_USER).sole.content
    assert_equal "what is going on", @conversation.title
  end

  test "a tool the agent reaches for is shown as a step" do
    fake(reply: "ok", steps: [ FirefightAi::AgentLoop::Step.new(key: "call_1", tool: "search_incidents", status: :running) ])
    Slack::Client.expects(:append_stream).with do |arguments|
      arguments[:chunks].sole[:title] == "Search incidents"
    end.returns({ ok: true })

    ask(@conversation, "what is going on")
  end

  test "the reply is streamed into the thread as the model writes it" do
    fake(reply: "The 14:02 deploy raised the pool size", pieces: [ "The 14:02 deploy ", "raised the pool size" ])
    appended = []
    Slack::Client.stubs(:append_stream).with { |arguments| appended << arguments[:chunks] }.returns({ ok: true })
    Slack::Client.expects(:stop_stream).with { |arguments| arguments[:blocks].nil? }.returns({ ok: true, ts: "1" })

    ask(@conversation, "what is going on")

    assert_equal [ { type: "markdown_text", text: "The 14:02 deploy raised the pool size" } ], appended.flatten
  end

  test "a reply Slack would not take mid stream is posted whole at the end" do
    fake(reply: "The 14:02 deploy raised the pool size", pieces: [ "The 14:02 deploy raised the pool size" ])
    Slack::Client.stubs(:append_stream).raises(AdapterError, "message_not_in_streaming_state")
    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:blocks].sole.dig(:text, :text).include?("14:02 deploy")
    end.returns({ ok: true, ts: "1" })

    ask(@conversation, "what is going on")
  end

  test "a channel reply is asked for in the markup Slack streams" do
    responder = fake(reply: "ok")

    ask(@conversation, "what is going on")

    assert_equal WorkspaceAdapter.for(@workspace).ai_stream_output_style, responder.options[:output_style]
  end

  test "a dashboard chat posts nothing, since the page reads the chat itself" do
    personal = personal_chat
    fake(reply: "The 14:02 deploy raised the pool size")
    Slack::Client.expects(:start_stream).never
    Slack::Client.expects(:post_message).never

    ask(personal, "what changed today")

    assert_equal "The 14:02 deploy raised the pool size",
                 personal.reload.chat.messages.where(role: "assistant").sole.content
  end

  test "a dashboard answer is asked for without Slack markup, because the page shows it as written" do
    personal = personal_chat
    responder = fake(reply: "ok")

    ask(personal, "what changed today")

    assert_equal Conversation::LiveDelivery::OUTPUT_STYLE, responder.options[:output_style]
  end

  test "a reply Slack refuses is logged rather than paid for twice" do
    fake(reply: "ok")
    Slack::Client.stubs(:stop_stream).raises(AdapterError, "channel_not_found")

    assert_nothing_raised { ask(@conversation, "what is going on") }
  end

  private

  # The question is written down by the asker, the way both entry points do it, and the job runs after.
  def ask(conversation, question)
    conversation.ask!(question)
    Conversation::Runner.new(conversation, asker: conversation.started_by).run
  end

  # The fake reads the chat off @conversation, so a dashboard chat takes that place for the turn.
  def personal_chat
    @conversation = Conversation.start_personal!(
      workspace: @workspace, member: workspace_memberships(:alice_workspace_one)
    )
  end

  def fake(outcome: FirefightAi::AgentLoop::STATUS_ANSWERED, reply: nil, turns: [], steps: [], pieces: [])
    responder = FakeResponder.new(
      -> { @conversation.reload.chat },
      outcome: FirefightAi::AgentLoop::Outcome.new(status: outcome, turns_used: turns.size, spent_micros: 0),
      reply: reply, turns: turns, steps: steps, pieces: pieces
    )
    FirefightAi::Responder.stubs(:new).with { |*, **options| responder.options = options }.returns(responder)
    responder
  end
end
