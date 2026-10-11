require "application_system_test_case"

# Halon's theory board sits under the step that last updated it, each cause with its status and evidence.
class AgentTheoryBoardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("Why is api erroring?")
    chat = @conversation.chat_record
    asked = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = asked.ruby_llm_tool_calls.create!(tool_call_id: "call_board", name: Chat::Tools::Theories::NAME, arguments: { "theories" => [ {}, {} ] })
    Chat::Theory.replace!(chat, [
      Chat::Theory::Given.new(title: "worker's deploy raised its database pool", status: Chat::Theory::STATUS_CONFIRMED, evidence: "logs: pool 40 since 13:38", leading: true),
      Chat::Theory::Given.new(title: "a slow query on orders", status: Chat::Theory::STATUS_RULED_OUT, evidence: "insights: p50 3 ms", leading: false)
    ], tool_call_id: "call_board")
    call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "Theory board"))
    @conversation.note!("worker's deploy raised its pool.")
    @conversation.reply_delivered!
  end

  test "the board shows each cause with its status, the leading one marked, and the evidence that settled it" do
    visit agent_chat_path(@conversation)

    assert_text(/confirmed · leading/i)
    assert_text "worker's deploy raised its database pool"
    assert_text(/ruled out/i)
    assert_text "insights: p50 3 ms"
  end
end
