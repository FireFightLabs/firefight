require "test_helper"

class Conversation::RunnerTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  # Stands in for the engine, so a turn's bookkeeping is tested without calling a model.
  class FakeResponder
    attr_reader :calls
    attr_accessor :options

    def initialize(chat, outcome:, reply: nil, turns: [], steps: [], pieces: [], take: false, during: nil)
      @during = during
      @take = take
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
      arguments[:take_messages].call if @take
      @during&.call(arguments)
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
    first.calls.sole[:tools].first.call(group: Chat::Tools::Groups::INCIDENT_HISTORY)

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

  test "the agent is told how the runs it started went, since a run answers after the turn that started it" do
    responder = fake(reply: "ok")
    run = @conversation.workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_CONVERSATION, conversation: @conversation, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
    run.conclude!(summary: "Checkout writes time out on the orders database")

    ask(@conversation, "what did it find")

    assert_match "checkout is slow: Checkout writes time out on the orders database", responder.calls.sole[:context]
  end

  test "the agent is handed the workspace's instructions, apart from what it remembers" do
    responder = fake(reply: "ok")
    Chat::Instruction.create!(workspace: @conversation.workspace, text: "Never restart the primary database")

    ask(@conversation, "what should we do")

    assert_match "never treat them as evidence:\n- Whole workspace: Never restart the primary database", responder.calls.sole[:context]
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

  test "a finished step streams to the dashboard what it got back, and a not found reads as one" do
    personal = personal_chat
    fake(reply: "It is a Worker", during: finished_step(personal, "Error: Cloudflare API error: 8000007: Project not found."))

    ask(personal, "is ember-landing a Pages project")

    shown = broadcasts(ConversationChannel.broadcasting_for(personal)).map { |message| JSON.parse(message) }
                                                                     .select { |event| event["type"] == Conversation::LiveDelivery::EVENT_STEP }.last
    assert_equal [ Conversation::LiveDelivery::STATUS_NOT_FOUND, Chat::StepOutcome::KIND_NOT_FOUND, "Cloudflare API error: 8000007: Project not found." ],
                 [ shown["status"], shown.dig("outcome", "kind"), shown.dig("outcome", "said") ]
  end

  test "a finished step in a thread says how it went in a word, a failure as an error" do
    reported = []
    Slack::Client.stubs(:append_stream).with { |arguments| reported.concat(arguments[:chunks]) }.returns({ ok: true })
    fake(reply: "ok", during: finished_step(@conversation, "Error: Cloudflare API error: 8000007: Project not found."))
    ask(@conversation, "is ember-landing a Pages project")
    fake(reply: "ok", during: finished_step(@conversation, "Error: Cloudflare API error: 10000: Authentication error", kind: Chat::StepOutcome::FAILURE_ERROR, id: "call_2"))
    ask(@conversation, "and now")

    finished = reported.select { |chunk| chunk[:type] == "task_update" && chunk[:status] != "in_progress" }
    assert_equal [ [ "complete", "Not found" ], [ "error", "Failed" ] ], finished.map { |chunk| chunk.values_at(:status, :output) }
  end

  test "an answer that rests on what a connected system showed is checked before it goes out" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    read = github.tools.create!(name: "fetch_file", description: "Read a file", read_only: true, enabled: true)
    responder = fake(reply: "ok", steps: [ FirefightAi::AgentLoop::Step.new(key: "call_1", tool: read.model_facing_name, status: :running) ])
    Slack::Client.stubs(:append_stream).returns({ ok: true })

    ask(@conversation, "why does billing fail")

    assert_equal FirefightAi::Responder::CHECK, responder.calls.sole[:check].call
  end

  test "an answer from Firefight's own records goes out as written" do
    responder = fake(reply: "ok", steps: [ FirefightAi::AgentLoop::Step.new(key: "call_1", tool: "search_incidents", status: :running) ])
    Slack::Client.stubs(:append_stream).returns({ ok: true })

    ask(@conversation, "what is going on")

    assert_nil responder.calls.sole[:check].call
  end

  test "a held draft is kept out of what the person reads" do
    responder = fake(reply: "ok")

    ask(@conversation, "what is going on")
    @conversation.chat.add_message(role: :assistant, content: "a draft")
    responder.calls.sole[:hold].call

    assert_not_includes @conversation.chat.readable_messages.map(&:content), "a draft"
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

  test "a dashboard chat is shown each time the turn made room, and a thread is not" do
    make_room = ->(arguments) { arguments[:memory].rebuild!(note: nil, tokens_before: 150_000) }
    personal = personal_chat
    fake(reply: "ok", during: make_room)

    ask(personal, "what changed today")

    made = broadcasts(ConversationChannel.broadcasting_for(personal)).map { |message| JSON.parse(message) }
                                                                     .select { |event| event["type"] == Conversation::LiveDelivery::EVENT_MADE_ROOM }
    assert_equal [ personal.chat.compactions.sole.step_key ], made.map { |event| event["key"] }

    @conversation = @workspace.conversations.create!(
      subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id, thread_id: "1700000000.000200",
      started_by: workspace_memberships(:alice_workspace_one), max_turns: 40, max_spend_cents: 50
    )
    fake(reply: "ok", during: make_room)
    Slack::Client.expects(:append_stream).never

    ask(@conversation, "what changed today")

    assert_equal 1, @conversation.chat.compactions.count
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

  # The page shows the agent working from this, so it has to be cleared by the turn itself and not by a reload.
  test "an answer is owed until the turn answers, and no longer once it has" do
    personal = personal_chat
    fake(reply: "The 14:02 deploy raised the pool size")

    ask(personal, "what changed today")

    assert_not personal.reload.answer_owed?
  end

  test "a turn that stops to ask the person no longer owes an answer, since the question is theirs now" do
    personal = personal_chat
    fake(outcome: FirefightAi::AgentLoop::STATUS_WAITING)
    Chat.any_instance.stubs(:to_llm).returns(stub(pending_approvals: []))

    ask(personal, "close every incident")

    assert_not personal.reload.answer_owed?
  end

  test "a category of integrations shown in a thread is posted under the answer, with a way to connect or manage each" do
    grafana = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana", settings: { "server_url" => "https://gf.example/mcp" })
    fake(reply: "Here are the telemetry tools.", steps: [
      FirefightAi::AgentLoop::Step.new(key: "call_1", tool: Mcp::Tools::LIST_INTEGRATIONS, status: FirefightAi::AgentLoop::STEP_RUNNING, arguments: { "category" => "observability" }),
      FirefightAi::AgentLoop::Step.new(key: "call_1", tool: nil, status: FirefightAi::AgentLoop::STEP_DONE)
    ])
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })
    Slack::Client.expects(:post_message).with do |arguments|
      blocks = arguments[:blocks].to_json
      arguments[:thread_ts] == @conversation.thread_id && blocks.include?("connect=datadog") && blocks.include?("integration=#{grafana.id}")
    end.returns({ ok: true, ts: "2" })

    with_app_host { ask(@conversation, "what can we connect for logs") }
  end

  test "a message sent while the agent works joins that turn, and the job queued behind it does not answer twice" do
    alice = workspace_memberships(:alice_workspace_one)
    responder = fake(reply: "Metrics show 5xx on web since 14:02", take: true)
    @conversation.ask!("anything in metrics?", asker: alice)
    @conversation.ask!("skip GitHub, only metrics", asker: alice)

    Conversation::Runner.new(@conversation, asker: alice).run
    second = Conversation::Runner.new(@conversation.reload, asker: alice).run

    assert_nil second
    assert_equal 1, responder.calls.size
    assert_equal [ "anything in metrics?", "skip GitHub, only metrics" ],
                 @conversation.chat.readable_messages.where(role: Chat::Message::ROLE_USER).map(&:content)
    assert_not @conversation.reload.answer_owed?
  end

  test "a connection's tools switched on since the last turn are told to the agent before the model is asked, as a note nobody reads" do
    alice = workspace_memberships(:alice_workspace_one)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    faylee.integration_environments.create!(credentials: { token: "x" }.to_json).store_fields!("project" => "faylee")
    tool = faylee.tools.create!(name: "api_request", description: "API", read_only: false, enabled: false, params_schema: { "type" => "object" })
    @conversation.ask!("scale faylee's web to 0", asker: alice)
    @conversation.chat_record.update!(connections_seen: Chat::Tools::Changes.snapshot(@workspace))
    tool.update!(enabled: true)
    fake(reply: "Done", take: true)

    Conversation::Runner.new(@conversation, asker: alice).run

    note = @conversation.chat.messages.find_by!(role: Chat::Message::ROLE_USER, nudge: true)
    assert_match "Faylee (Northflank) had faylee_api_request switched on.", note.content
    assert_equal [ "scale faylee's web to 0" ], @conversation.chat.readable_messages.where(role: Chat::Message::ROLE_USER).map(&:content)
  end

  test "a connection switched on while the agent works is told at its next step" do
    alice = workspace_memberships(:alice_workspace_one)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    faylee.integration_environments.create!(credentials: { token: "x" }.to_json)
    tool = faylee.tools.create!(name: "api_request", description: "API", read_only: false, enabled: false, params_schema: { "type" => "object" })
    @conversation.ask!("scale faylee's web to 0", asker: alice)
    told = nil
    fake(reply: "Done", during: lambda { |arguments|
      tool.update!(enabled: true)
      told = arguments[:take_messages].call
    })

    Conversation::Runner.new(@conversation, asker: alice).run

    assert told
    assert_match "Faylee (Northflank) had faylee_api_request switched on.", @conversation.chat.messages.find_by!(nudge: true).content
  end

  test "someone else's message waits for their own turn, since a turn acts with its asker's permissions" do
    alice = workspace_memberships(:alice_workspace_one)
    bob = workspace_memberships(:bob_workspace_one)
    responder = fake(reply: "Here is what I found", take: true)
    @conversation.ask!("anything in metrics?", asker: alice)
    @conversation.ask!("resolve it", asker: bob)

    Conversation::Runner.new(@conversation, asker: alice).run
    Conversation::Runner.new(@conversation.reload, asker: bob).run

    assert_equal 2, responder.calls.size
    assert_equal "resolve it", @conversation.chat.readable_messages.where(role: Chat::Message::ROLE_USER).last.content
  end

  # Seen in a real chat. A confirmed call never got its result, and the provider refused every question after it.
  test "a question after a call left without its result is answered, not refused" do
    personal = personal_chat
    chat = personal.chat_record
    chat.add_message(role: :user, content: "Which pipeline deploys Firefight?")
    asking = chat.add_message(role: :assistant, content: "")
    asking.ruby_llm_tool_calls.create!(tool_call_id: "call_jY", name: "northflank_api_request", arguments: {}, approval: Chat::APPROVAL_APPROVED)
    personal.ask!("Does Northflank post deploys to Slack?")
    fake(reply: "No, nothing posts deploys to Slack", during: refuse_unanswered_calls)

    ConversationReplyJob.perform_now(personal.id, personal.started_by.id)

    assert_equal "No, nothing posts deploys to Slack", personal.chat.reload.readable_messages.last.content
    assert personal.chat.tool_calls.find_by!(tool_call_id: "call_jY").result_id
  end

  # Seen in a real chat too. The person asked something new while Halon waited for them to confirm a call.
  test "a question asked while a call waits to be confirmed is answered, and the confirmation is withdrawn" do
    personal = personal_chat
    chat = personal.chat_record
    chat.add_message(role: :user, content: "Restart web")
    asking = chat.add_message(role: :assistant, content: "")
    asking.ruby_llm_tool_calls.create!(tool_call_id: "call_r", name: "restart", arguments: {})
    chat.request_decisions!([ "call_r" ])
    personal.ask!("Actually, what changed today?")
    fake(reply: "A deploy at 14:02", during: refuse_unanswered_calls)

    ConversationReplyJob.perform_now(personal.id, personal.started_by.id)

    assert_equal "A deploy at 14:02", personal.chat.reload.readable_messages.last.content
    assert_empty personal.chat.awaiting_decision
  end

  test "a turn keeps the answer it is writing in the thread until it is finished there" do
    seen = []
    fake(reply: "A deploy at 14:02", pieces: [ "A deploy at 14:02 raised the pool size. " * 10 ], during: ->(_arguments) { seen << @conversation.reload.slice(:answer_message_id, :answer_shown) })
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1234567890.000100" })

    ask(@conversation, "what changed")

    assert_equal [ { "answer_message_id" => "1234567890.000100", "answer_shown" => true } ], seen
    assert_nil @conversation.reload.answer_message_id
  end

  test "a confirmation in a thread is kept where it was posted, and redrawn as withdrawn once the person moves past it" do
    pause = lambda do |_arguments|
      asking = @conversation.chat.add_message(role: :assistant, content: "")
      asking.ruby_llm_tool_calls.create!(tool_call_id: "call_r", name: "restart", arguments: {})
    end
    fake(outcome: FirefightAi::AgentLoop::STATUS_WAITING, during: pause)
    Chat.any_instance.stubs(:to_llm).returns(stub(pending_approvals: [ stub(id: "call_r") ]))
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1700000000.000200" })
    ask(@conversation, "restart web")
    Chat.any_instance.unstub(:to_llm)
    assert_equal "1700000000.000200", @conversation.reload.confirmation_message_id

    fake(reply: "A deploy at 14:02")
    Slack::Client.expects(:update_message).with do |arguments|
      shown = arguments[:blocks].to_json
      arguments[:ts] == "1700000000.000200" && shown.include?("Withdrawn") && !shown.include?(Identifiers::AGENT_CONFIRM)
    end.returns({ ok: true, ts: "1700000000.000200" })
    ask(@conversation.reload, "Actually, what changed today?")

    assert_equal Chat::APPROVAL_WITHDRAWN, @conversation.chat.tool_calls.find_by!(tool_call_id: "call_r").approval
  end

  test "a stop ends the turn where it is, answers any tool it never ran, and says Stopped" do
    call_asked_for = lambda do |_arguments|
      reply = @conversation.chat.add_message(role: :assistant, content: "")
      reply.ruby_llm_tool_calls.create!(tool_call_id: "call_9", name: "search_logs", arguments: {})
      @conversation.request_stop!
    end
    fake(outcome: FirefightAi::AgentLoop::STATUS_CANCELED, during: call_asked_for)
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })

    outcome = ask(@conversation, "anything in metrics?")

    chat = @conversation.chat.reload
    assert_equal FirefightAi::AgentLoop::STATUS_CANCELED, outcome.status
    assert_equal Conversation::Runner::STOPPED_BEFORE_RUNNING, chat.tool_calls.find_by!(tool_call_id: "call_9").result.content
    assert_equal Conversation::Runner::STOPPED, chat.readable_messages.last.content
    assert_not chat.stop_requested?
    assert_not @conversation.reload.answer_owed?
  end

  test "a stop that lands while the model is answering ends the turn the same way" do
    fake(during: ->(_arguments) { raise FirefightAi::Canceled, "cancelled" })
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })

    ask(@conversation, "anything in metrics?")

    assert_equal Conversation::Runner::STOPPED, @conversation.chat.readable_messages.last.content
  end

  test "a stop pressed while the turn waited to start ends it before the model is asked" do
    responder = fake(reply: "never")
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })
    @conversation.ask!("anything in metrics?")
    @conversation.request_stop!

    Conversation::Runner.new(@conversation, asker: @conversation.started_by).run

    assert_empty responder.calls
    assert_equal Conversation::Runner::STOPPED, @conversation.chat.readable_messages.last.content
  end

  test "a stop that lands as the answer finishes does not stop the next question" do
    responder = fake(reply: "Web is fine", during: ->(_arguments) { @conversation.request_stop! })
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })
    ask(@conversation, "anything in metrics?")

    assert_not @conversation.chat.reload.stop_requested?
    assert_equal 1, responder.calls.size
  end

  test "stopping needs an answer to be under way" do
    assert_equal Conversation::NOTHING_TO_STOP, @conversation.stop_blocked_reason

    @conversation.ask!("anything in metrics?")

    assert_nil @conversation.stop_blocked_reason
  end

  test "an admin's first answered chat finishes setup's Meet Halon step, and a stopped one does not" do
    onboarding = @workspace.create_onboarding!(installer: workspace_memberships(:alice_workspace_one))
    personal_chat
    fake(outcome: FirefightAi::AgentLoop::STATUS_CANCELED)
    ask(@conversation, "what runs where")
    assert_nil onboarding.reload.halon_answered_at

    fake(reply: "Two services on Northflank")
    ask(@conversation, "what runs where")
    assert onboarding.reload.halon_answered_at
  end

  private

  def with_app_host
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "app.example.com"
    yield
  ensure
    ENV["APP_HOST"] = previous
  end

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

  # A call the agent made and the provider failed, saved and marked as the wrapper does, then reported done by the loop.
  def finished_step(conversation, said, kind: Chat::StepOutcome::FAILURE_NOT_FOUND, id: "call_1")
    lambda do |arguments|
      chat = conversation.reload.chat
      asking = chat.add_message(role: :assistant, content: "")
      result = chat.add_message(role: :tool, content: FirefightAi::Evidence.frame("search_incidents", said))
      RubyLLM::ActiveRecord::ToolCall.create!(message: asking, tool_call_id: id, name: "search_incidents", arguments: { "query" => "ember" },
                                              result: result, failed: true, failure_kind: kind)
      arguments[:on_step].call(FirefightAi::AgentLoop::Step.new(key: id, tool: "search_incidents", status: :running, arguments: { "query" => "ember" }))
      arguments[:on_step].call(FirefightAi::AgentLoop::Step.new(key: id, tool: nil, status: :done, arguments: nil))
    end
  end

  # What a provider does with a chat that has anything but results between a call and the next message.
  def refuse_unanswered_calls
    lambda do |_arguments|
      sent = @conversation.chat.reload.sent_messages.to_a
      sent.each_with_index do |message, index|
        results = sent.drop(index + 1).take_while { |later| later.role == Chat::Message::ROLE_TOOL }
        missing = message.ruby_llm_tool_calls.map(&:tool_call_id) - results.filter_map { |result| result.ruby_llm_parent_tool_call&.tool_call_id }
        raise FirefightAi::TerminalError, "Provider returned error - No tool output found for function call #{missing.first}." if missing.any?
      end
    end
  end

  def fake(outcome: FirefightAi::AgentLoop::STATUS_ANSWERED, reply: nil, turns: [], steps: [], pieces: [], take: false, during: nil)
    responder = FakeResponder.new(
      -> { @conversation.reload.chat },
      outcome: FirefightAi::AgentLoop::Outcome.new(status: outcome, turns_used: turns.size, spent_micros: 0),
      reply: reply, turns: turns, steps: steps, pieces: pieces, take: take, during: during
    )
    FirefightAi::Responder.stubs(:new).with { |*, **options| responder.options = options }.returns(responder)
    responder
  end
end
