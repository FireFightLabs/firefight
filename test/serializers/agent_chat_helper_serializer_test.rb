require "test_helper"

class AgentChatHelperSerializerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    chat = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one)).chat_record
    @helper = Chat::Helper.start!(chat: chat, tool_call_id: "call_1", since: 1.minute.ago,
                                  checks: [ Chat::Helpers::Check.new(title: "Logs", brief: "Read the logs", deep: false) ]).sole
    own = Chat.open!(owner: @helper, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o-mini"))
    asked = own.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asked.ruby_llm_tool_calls.create!(tool_call_id: "h_1", name: Mcp::Tools::SEARCH_INCIDENTS, arguments: { "query" => "checkout" })
  end

  test "a step left open by a helper that has ended reads as cancelled, never as still running" do
    assert_equal Conversation::LiveDelivery::STATUS_RUNNING, shown["steps"].sole["status"]

    @helper.finish!(Chat::Helper::STATUS_STOPPED, ended_because: Chat::Helper::STOPPED)

    assert_equal [ Conversation::LiveDelivery::STATUS_CANCELLED, Chat::Helper::STOPPED, nil ],
                 [ shown["steps"].sole["status"], shown["endedBecause"], shown["report"] ]
  end

  private

  def shown = AgentChatHelperSerializer.one(@helper.reload).deep_stringify_keys
end
