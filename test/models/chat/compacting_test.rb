require "test_helper"

class Chat::CompactingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @chat = @workspace.chats.create!(owner: @investigation, model: "claude-sonnet-4-5", provider: :anthropic)
    @chat.add_message(role: :system, content: "You are an SRE.")
    @chat.add_message(role: :user, content: "Investigate this incident.")
  end

  test "clearing replaces old tool results with a line saying where the full text is, and keeps the newest whole" do
    8.times { |number| tool_turn(number + 1) }

    freed = @chat.clear_old_results!(tokens_before: 90_000)

    assert_operator freed, :>, 0
    results = @chat.messages.where(role: "tool").order(:created_at).to_a
    assert_equal 8 - Chat::Compacting::KEEP_RECENT, results.count { |message| message.content.include?("Shortened to save room") }
    assert results.last(Chat::Compacting::KEEP_RECENT).none? { |message| message.content.include?("Shortened") }
  end

  test "what was cleared is kept in full and can be read again by the name in its place" do
    8.times { |number| tool_turn(number + 1) }

    @chat.clear_old_results!(tokens_before: 90_000)

    cleared = @chat.messages.where(role: "tool").order(:created_at).first
    handle = cleared.content[/result_\d+/]
    saved = @chat.saved_results.find_by!(handle: handle)
    assert_match "log line 1 ", saved.content
    assert_no_match(/tool_result/, saved.content, "the frame is the model's view, the saved text is what the tool said")
    assert_equal 1, saved.step
  end

  test "a cleared result still says which tool and which step it was, so a citation keeps meaning something" do
    8.times { |number| tool_turn(number + 1) }

    @chat.clear_old_results!(tokens_before: 90_000)

    cleared = @chat.messages.where(role: "tool").order(:created_at).first.content
    assert cleared.start_with?("<tool_result tool=\"log_query\" step=\"1\" trust=\"untrusted\">")
    assert cleared.end_with?("</tool_result>")
  end

  test "clearing that would free too little does nothing, since every clear costs the cache" do
    (Chat::Compacting::KEEP_RECENT + 1).times { |number| tool_turn(number + 1, lines: 2) }

    assert_equal 0, @chat.clear_old_results!(tokens_before: 90_000)
    assert_empty @chat.compactions
  end

  test "a result that was already saved because it was large is pointed at, not saved twice" do
    saved = @chat.saved_results.keep!(tool_name: "log_query", text: "huge", step: 1)
    tool_turn(1, body: FirefightAi::Evidence.preview("x\n" * 50_000, handle: saved.handle, read_with: "read_result"))
    7.times { |number| tool_turn(number + 2) }

    @chat.clear_old_results!(tokens_before: 90_000)

    assert_equal 1, @chat.saved_results.where(step: 1).count
    assert_match saved.handle, @chat.messages.where(role: "tool").order(:created_at).first.content
  end

  test "every clear is written down with what it freed" do
    8.times { |number| tool_turn(number + 1) }

    @chat.clear_old_results!(tokens_before: 90_000)

    event = @chat.compactions.sole
    assert_equal Chat::Compaction::STAGE_CLEARED, event.stage
    assert_equal 90_000, event.tokens_before
    assert_operator event.tokens_freed, :>, 0
  end

  test "a rebuild stops sending the old messages without deleting them, and starts again from the state and the note" do
    3.times { |number| tool_turn(number + 1) }
    sent_before = @chat.sent_messages.count

    @chat.rebuild!(note: "The deploy at 14:02 looks guilty. Next I was going to read the pool config.", tokens_before: 150_000)

    assert_equal sent_before + 1, @chat.messages.count, "nothing is deleted"
    sent = @chat.sent_messages.to_a
    assert_equal %w[system user], sent.map(&:role)
    assert sent.last.nudge, "the fresh start is Firefight speaking, not the person"
    assert_match "The deploy at 14:02 looks guilty", sent.last.content
    assert_match "step 1", sent.last.content
  end

  test "a chat keeps what the person and the agent said to each other, and drops only the work in between" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.add_message(role: :user, content: "What changed today?")
    tool_turn(1, chat: chat, step: nil)
    chat.add_message(role: :assistant, content: "Two deploys went out.")

    chat.rebuild!(note: "They care about checkout.", tokens_before: 150_000)

    assert_equal [ "What changed today?", "Two deploys went out." ], chat.sent_messages.where(nudge: false).map(&:content)
    assert chat.sent_messages.where(role: "tool").none?
  end

  test "the agent's note to itself is never shown to the person as something it said to them" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.add_message(role: :user, content: "What changed today?")
    chat.add_message(role: :assistant, content: "They care about checkout. Next I was going to read the deploys.")

    chat.rebuild!(note: "They care about checkout. Next I was going to read the deploys.", tokens_before: 150_000)

    assert_equal [ "What changed today?" ], chat.readable_messages.map(&:content)
  end

  test "a rebuild with no note still starts again from the state, for when the model could not be asked" do
    tool_turn(1)

    @chat.rebuild!(note: nil, tokens_before: 210_000)

    assert_match "step 1", @chat.sent_messages.last.content
    assert_equal Chat::Compaction::STAGE_REBUILT, @chat.compactions.sole.stage
  end

  test "the state names every theory with where it stands and what it rests on" do
    tool_turn(1)
    @investigation.steps.create!(
      position: 1, tool_name: "log_query", label: "Log query errors", action_key: "datadog.log_query",
      status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current
    )
    @investigation.record_hypothesis!(assertion: "The pool is exhausted", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])

    @chat.rebuild!(note: nil, tokens_before: 150_000)

    assert_match(/The pool is exhausted.*supported.*step 1/m, @chat.sent_messages.last.content)
  end

  private

  def tool_turn(number, chat: @chat, lines: 400, body: nil, step: number)
    call_id = "call_#{number}"
    chat.add_message(RubyLLM::Message.new(
      role: :assistant, content: "",
      tool_calls: { call_id => RubyLLM::ToolCall.new(id: call_id, name: "log_query", arguments: { "query" => "errors #{number}" }) }
    ))
    text = body || (1..lines).map { |line| "log line #{number} #{line} connection pool exhausted" }.join("\n")
    chat.add_message(role: :tool, content: FirefightAi::Evidence.frame("log_query", text, step: step), tool_call_id: call_id)
  end
end
