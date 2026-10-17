require "application_system_test_case"

# An answer lists what Halon read to give it, folded under the answer so it is there when someone checks.
class AgentAnswerSourcesTest < ApplicationSystemTestCase
  RUN = "https://app.northflank.com/t/larkspur/project/shop/workflows/release/runs/4182".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("How did the release go?")
    chat = @conversation.chat_record
    asked = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = asked.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: FirefightTools::SEARCH_INCIDENTS, arguments: { "query" => "release" })
    call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "Run 4182 failed at migrate. #{RUN}"))
    @conversation.note!("Run 4182 failed at its migrate step.")
    @conversation.reply_delivered!
  end

  test "the sources sit folded under the answer and open to each one linked" do
    visit agent_chat_path(@conversation)

    assert_text "Run 4182 failed at its migrate step."
    toggle = find("button", text: "Read 1 source")
    assert_no_link href: RUN
    toggle.click
    assert_link "Search incidents release", href: RUN
  end
end
