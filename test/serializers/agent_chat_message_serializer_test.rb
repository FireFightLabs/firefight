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

  private

  def statuses(message) = JSON.parse(AgentChatMessageSerializer.one(message.reload).to_json)["tools"].map { |tool| tool["status"] }

  def tools = JSON.parse(AgentChatMessageSerializer.one(@asking.reload).to_json)["tools"]
end
