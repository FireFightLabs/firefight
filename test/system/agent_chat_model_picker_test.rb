require "application_system_test_case"

class AgentChatModelPickerTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    sign_in(users(:alice), @workspace)
  end

  test "switching an open chat's model says so, and each answer names the model that wrote it" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("what changed today")
    reply = conversation.chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "Nothing changed today.")
    RubyLLM::ActiveRecord::Usage.create!(chat: conversation.chat, message: reply, operation: "chat", provider: "openrouter",
                                         model: "z-ai/glm-5.2", status: "succeeded")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)

    assert_text "Nothing changed today."
    assert_selector "p", exact_text: "GLM-5.2"
    find("button[aria-label='Model: Shared Vision. Choose another']").click
    assert_text "Strongest, slower and pricier"
    find("[role=menuitemradio]", text: "Claude Opus 5.5").click

    assert_text "This chat now uses Claude Opus 5.5."
    assert_selector "button[aria-label='Model: Claude Opus 5.5. Choose another']"
    assert_equal "anthropic/claude-opus-5.5", conversation.reload.chosen_model
  end

  test "a model picked before the first question starts the new chat on it" do
    visit agent_chats_path

    find("button[aria-label='Model: Shared Vision. Choose another']").click
    find("[role=menuitemradio]", text: "GLM-5.2").click
    assert_selector "button[aria-label='Model: GLM-5.2. Choose another']"
    find("textarea[aria-label='Prompt']").send_keys("Which incidents are open?", :enter)

    assert_selector "section.agent-thread-open"
    assert_selector "button[aria-label='Model: GLM-5.2. Choose another']"
    assert_equal "z-ai/glm-5.2", @workspace.conversations.personal.find_by!(started_by: @member).chosen_model
  end
end
