require "test_helper"

# A code fix runs for minutes. What its coding agent does reaches the chat's step as it happens: live on the dashboard,
# kept with the chat for a reload or a second viewer, and in a Slack thread as the step's one line, redrawn at Slack's pace.
class Conversation::CodeFixProgressTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  # Stands in for the engine: the call is saved, reported running, works through the turn's listener, then ends.
  class FakeResponder
    def initialize(chat, during)
      @chat = chat
      @during = during
    end

    def run(**arguments)
      chat = @chat.call
      llm_call = RubyLLM::ToolCall.new(id: "call_1", name: "search_incidents", arguments: { "query" => "pool" })
      asking = chat.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_1" => llm_call }))
      arguments[:on_step].call(FirefightAi::AgentLoop::Step.new(key: "call_1", tool: "search_incidents", status: :running, arguments: { "query" => "pool" }))
      @during.call
      result = chat.add_message(role: :tool, content: "Opened https://github.com/acme/api/pull/7")
      asking.ruby_llm_tool_calls.find_by!(tool_call_id: "call_1").update!(result: result)
      arguments[:on_step].call(FirefightAi::AgentLoop::Step.new(key: "call_1", tool: nil, status: :done, arguments: nil))
      chat.add_message(role: :assistant, content: "Opened the pull request.")
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
    end

    def ai_model = FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @work = Chat::CodeFixProgress.start
    stub_post_message
    stub_agent_session
  end

  test "the dashboard sees each thing the agent did as it happens, and the step ends with its summary" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    run_turn(conversation) do |report|
      @work.add("Read config/database.yml")
      report.call(@work)
      travel 2.seconds
      @work.add("Edited config/database.yml")
      @work.changed!("config/database.yml")
      report.call(@work)
      report.call(@work)
      opened!
      report.call(@work)
    end

    events = broadcasts(ConversationChannel.broadcasting_for(conversation)).map { |message| JSON.parse(message) }
                                                                          .select { |event| event["type"] == Conversation::LiveDelivery::EVENT_STEP }
    running = events.select { |event| event["status"] == Conversation::LiveDelivery::STATUS_RUNNING && event["progress"] }
    assert_equal [ 1, 2, 2 ], running.map { |event| event.dig("progress", "total") }, "a repeat is never sent twice"
    done = events.last
    assert_equal Conversation::LiveDelivery::STATUS_DONE, done["status"]
    assert_equal [ "opened", "https://github.com/acme/api/pull/7" ], done["progress"].values_at("outcome", "pullRequest")
  end

  test "a reload or a second viewer sees what arrived live, kept with the chat" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    seen_mid_run = nil
    run_turn(conversation) do |report|
      @work.add("Ran bin/rails test test/pool_test.rb", result: Chat::CodeFixProgress::RESULT_FAILED)
      @work.tested!("bin/rails test test/pool_test.rb", passed: false)
      report.call(@work)
      seen_mid_run = shown_step(conversation)
      opened!
      report.call(@work)
    end

    assert_equal [ "Ran bin/rails test test/pool_test.rb" ], seen_mid_run.dig(:progress, "lines").map { |line| line["text"] }
    assert_nil seen_mid_run.dig(:progress, "outcome")
    after = shown_step(conversation)
    assert_equal [ "opened", [ [ "config/database.yml", 1, 1 ] ] ],
                 [ after.dig(:progress, "outcome"), after.dig(:progress, "files").map { |file| file.values_at("path", "added", "removed") } ]
    kept = Chat::StepProgress.find_by!(chat: conversation.chat, tool_call_id: "call_1")
    assert_not_includes kept.read_attribute_before_type_cast(:progress), "pool_test", "kept encrypted, like the chat's messages"
  end

  test "a Slack thread shows the latest thing and the counts as the step's details, redrawn at most every few seconds" do
    incident = incidents(:active_critical_ws1)
    conversation = @workspace.conversations.create!(
      subject: incident, kind: Conversation::KIND_CHANNEL, channel_id: incident.channel_id, thread_id: "1700000000.000100",
      started_by: @alice, max_turns: 40, max_spend_cents: 50
    )
    reported = []
    Slack::Client.stubs(:append_stream).with { |arguments| reported.concat(arguments[:chunks]) }.returns({ ok: true })

    run_turn(conversation) do |report|
      20.times do |number|
        @work.add("Read file#{number}.rb")
        report.call(@work)
      end
      travel Slack::WorkspaceAdapter::AGENT_STEP_UPDATE_INTERVAL.seconds + 1.second
      @work.add("Ran bin/rails test", result: Chat::CodeFixProgress::RESULT_PASSED)
      @work.tested!("bin/rails test", passed: true)
      report.call(@work)
      opened!
      report.call(@work)
    end

    detailed = reported.select { |chunk| chunk[:type] == "task_update" && chunk[:details] }
    assert_equal [ "Read file0.rb · 1 step", "Ran bin/rails test · 21 steps · tests passed",
                   "Opened the pull request · 21 steps · 1 file changed · tests passed", "Opened the pull request · 21 steps · 1 file changed · tests passed" ],
                 detailed.map { |chunk| chunk[:details] }
    assert_equal [ "in_progress", "in_progress", "in_progress", "complete" ], detailed.map { |chunk| chunk[:status] }
  end

  test "a sentence of progress from another tool is not shown in a chat, as before" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    run_turn(conversation) { |report| report.call("Devin is writing the change.") }

    assert_not Chat::StepProgress.exists?(chat: conversation.chat)
  end

  private

  def opened!
    @work.changed!("config/database.yml")
    @work.opened!(files: { "config/database.yml" => [ 1, 1 ] }, pull_request: "https://github.com/acme/api/pull/7")
  end

  # The turn's listener is what a tool call reports to, the same one Chat::Tools::Connection hands the executor.
  def run_turn(conversation, &work)
    turn = Conversation::Turn.new(conversation, asker: @alice)
    Conversation::Turn.stubs(:new).returns(turn)
    FirefightAi::Responder.stubs(:new).returns(FakeResponder.new(-> { conversation.reload.chat }, -> { work.call(turn.progress_listener("call_1")) }))
    conversation.ask!("fix the pool")
    Conversation::Runner.new(conversation, asker: @alice).run
  end

  def shown_step(conversation)
    messages = conversation.chat.readable_messages.includes(:attached_files, ruby_llm_tool_calls: :result)
    messages.flat_map { |message| AgentChatMessageSerializer.one(message)[:tools] }.find { |step| step[:key] == "call_1" }
  end
end
