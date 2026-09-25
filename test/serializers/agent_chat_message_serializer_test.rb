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

  private

  def tools = JSON.parse(AgentChatMessageSerializer.one(@asking.reload).to_json)["tools"]
end
