require "test_helper"

class AgentChatMessageSerializerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    @chat.add_message(role: :user, content: "How is checkout doing?")
    @asking = @chat.add_message(role: :assistant, content: "")
    result = @chat.add_message(role: :tool, content: "web-1: max 42")
    RubyLLM::ActiveRecord::ToolCall.create!(message: @asking, tool_call_id: "call_7", name: "northflank_query_metrics", arguments: {}, result: result)
  end

  test "a finished step that drew charts carries the chart card, and one that did not carries none" do
    assert_nil tools.sole["card"]

    Chat::Chart.record!(@chat, "call_7", [ { "title" => "5xx responses of web", "from" => "2026-09-25T14:00:00Z", "to" => "2026-09-25T15:00:00Z", "series" => [] } ])

    assert_equal Chat::Tools::CARD_CHART, tools.sole.dig("card", "kind")
  end

  test "a chart an earlier question's call drew under the same id never marks a later call as charted" do
    Chat::Chart.record!(@chat, "call_7", [ { "title" => "Memory of web", "from" => "2026-09-25T14:00:00Z", "to" => "2026-09-25T15:00:00Z", "series" => [] } ])
    travel 1.minute
    @chat.add_message(role: :user, content: "Did the pull request open?")
    later = @chat.add_message(role: :assistant, content: "")
    answer = @chat.add_message(role: :tool, content: "PR #856 is open")
    RubyLLM::ActiveRecord::ToolCall.create!(message: later, tool_call_id: "call_7", name: "github_pr_lookup", arguments: {}, result: answer)

    pages = AgentChatMessageSerializer::Page.new([ @asking, later ])
    assert pages.charted?(@asking.reload, "call_7")
    assert_not pages.charted?(later.reload, "call_7")
  end

  test "a page of one message still knows a later call by the same id, so the later call's chart is never the earlier one's" do
    travel 1.minute
    later = @chat.add_message(role: :assistant, content: "")
    RubyLLM::ActiveRecord::ToolCall.create!(message: later, tool_call_id: "call_7", name: "northflank_query_metrics", arguments: {})
    travel 1.minute
    Chat::Chart.record!(@chat, "call_7", [ { "title" => "Memory of web", "from" => "2026-09-25T14:00:00Z", "to" => "2026-09-25T15:00:00Z", "series" => [] } ])

    assert_not AgentChatMessageSerializer::Page.new([ @asking.reload ]).charted?(@asking, "call_7")
    assert AgentChatMessageSerializer::Page.new([ later.reload ]).charted?(later, "call_7")
  end

  test "a coding agent's work under a call id an earlier question used stays with each call, and neither overwrites the other" do
    first = Chat::CodeFixProgress.start
    first.add("Edited the checkout retry")
    Chat::StepProgress.keep!(@chat, "call_7", first, since: @asking.created_at)
    travel 1.minute
    @chat.add_message(role: :user, content: "Fix the pull request too")
    later = @chat.add_message(role: :assistant, content: "")
    RubyLLM::ActiveRecord::ToolCall.create!(message: later, tool_call_id: "call_7", name: "github_fix_code", arguments: {})
    second = Chat::CodeFixProgress.start
    second.add("Edited the review comments")
    Chat::StepProgress.keep!(@chat, "call_7", second, since: later.created_at)

    pages = AgentChatMessageSerializer::Page.new([ @asking.reload, later.reload ])
    assert_equal 2, @chat.step_progresses.where(tool_call_id: "call_7").count
    assert_equal [ "Edited the checkout retry" ], pages.work(@asking, "call_7").lines.map(&:text)
    assert_equal [ "Edited the review comments" ], pages.work(later, "call_7").lines.map(&:text)
  end

  test "a finished step carries what it got back, and a call the provider answered not found shows as not found" do
    assert_equal [ Conversation::LiveDelivery::STATUS_DONE, Chat::StepOutcome::KIND_ANSWERED, [ "web-1: max 42" ] ],
                 [ tools.sole["status"], tools.sole.dig("outcome", "kind"), tools.sole.dig("outcome", "lines") ]

    @chat.mark_failed!("call_7", kind: Chat::StepOutcome::FAILURE_NOT_FOUND)
    assert_equal [ Conversation::LiveDelivery::STATUS_NOT_FOUND, "web-1: max 42" ], [ tools.sole["status"], tools.sole.dig("outcome", "said") ]

    @chat.mark_failed!("call_7")
    assert_equal [ Conversation::LiveDelivery::STATUS_FAILED, Chat::StepOutcome::KIND_FAILED ], [ tools.sole["status"], tools.sole.dig("outcome", "kind") ]
  end

  test "an approved call waits while another asked with it is open, and runs once none is" do
    paused = @chat.add_message(role: :assistant, content: "")
    %w[call_8 call_9].each { |id| RubyLLM::ActiveRecord::ToolCall.create!(message: paused, tool_call_id: id, name: "delete_permission_set", arguments: {}) }
    @chat.request_decisions!(%w[call_8 call_9])
    @chat.decide!("call_8", approved: true)

    assert_equal [ Conversation::LiveDelivery::STATUS_WAITING ] * 2, statuses(paused)

    @chat.decide!("call_9", approved: true)
    assert_equal [ Conversation::LiveDelivery::STATUS_RUNNING ] * 2, statuses(paused)
  end

  test "a call cut off before it answered shows as not finished, in words, rather than spinning" do
    cut_off = @chat.add_message(role: :assistant, content: "")
    RubyLLM::ActiveRecord::ToolCall.create!(message: cut_off, tool_call_id: "call_8", name: "northflank_query_metrics", arguments: {})
    @chat.add_message(role: :user, content: "Still there?")

    @chat.close_unfinished_calls!

    step = JSON.parse(AgentChatMessageSerializer.one(cut_off.reload).to_json)["tools"].sole
    assert_equal Conversation::LiveDelivery::STATUS_FAILED, step["status"]
    assert_match "Interrupted before it finished", step.dig("outcome", "said")
  end

  test "a message says when it was written, to the millisecond, so the times Halon made room fall in the right place" do
    shown = JSON.parse(AgentChatMessageSerializer.one(@asking.reload).to_json)

    assert_equal @asking.created_at.utc.iso8601(3), shown["createdAt"]
  end

  test "what Halon wrote before carrying on is a status line, and the turn's last words are a message, the same on any page" do
    @asking.update!(content: "Plan: read checkout's metrics, then answer.")
    answer = @chat.add_message(role: :assistant, content: "Checkout is healthy.")

    shown = JSON.parse(AgentChatMessageSerializer.many(@chat.messages.where(role: Chat::Message::READABLE_ROLES).order(:created_at).to_a).to_json)
    assert_equal [ nil, Chat::TurnText::STATUS, Chat::TurnText::RESULT ], shown.map { |message| message["saidAs"] }

    older_page = JSON.parse(AgentChatMessageSerializer.many([ @asking.reload ]).to_json)
    assert_equal Chat::TurnText::STATUS, older_page.sole["saidAs"]
    assert_equal Chat::TurnText::RESULT, JSON.parse(AgentChatMessageSerializer.one(answer).to_json)["saidAs"]
  end

  test "a step says the provider it went through, and a call no connection holds names none" do
    assert tools.sole.key?("source")
    assert_nil tools.sole["source"]
  end

  private

  def statuses(message) = JSON.parse(AgentChatMessageSerializer.one(message.reload).to_json)["tools"].map { |tool| tool["status"] }

  def tools = JSON.parse(AgentChatMessageSerializer.one(@asking.reload).to_json)["tools"]
end
