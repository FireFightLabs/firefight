require "application_system_test_case"

class AgentChatListTest < ApplicationSystemTestCase
  setup do
    workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
  end

  # The browser is shared across tests, so the remembered state is cleared for the next one. A blank page
  # refuses storage, which is fine, since it then holds nothing to clear.
  teardown do
    page.execute_script("try { window.localStorage.clear() } catch (error) {}")
  end

  test "the chat list hides, stays hidden after a reload, and comes back" do
    visit agent_chats_path
    assert_selector "aside.agent-chat-list", text: "Chats"

    click_button "Hide chats"
    assert_selector ".agent-chat[data-list=collapsed]"
    assert_no_selector "aside.agent-chat-list", visible: true

    visit agent_chats_path
    assert_selector ".agent-chat[data-list=collapsed]"
    assert_selector "button[aria-label='New chat']", visible: true

    click_button "Show chats"
    assert_selector ".agent-chat[data-list=open]"
    assert_selector "aside.agent-chat-list", text: "Chats", visible: true
  end

  # A step that finished before the chat opened shows finished. It once replayed as running, one step after
  # another, which opened and closed its card every time the chat was opened.
  test "an opened chat shows its finished steps as finished, with no replay" do
    conversation = Conversation.start_personal!(workspace: workspaces(:slack_workspace_one), member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("how is checkout doing")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "northflank_query_metrics", arguments: { "resource" => "checkout" })
    conversation.chat.add_message(role: :tool, content: "5xx responses of checkout", tool_call_id: "call_1")
    conversation.note!("Checkout is healthy.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)
    page.execute_script(<<~JS)
      window.__ranAgain = false
      const watch = () => { if (document.querySelector("svg[style*='spin']")) { window.__ranAgain = true } }
      watch()
      new MutationObserver(watch).observe(document.body, { subtree: true, childList: true, attributes: true })
    JS
    assert_text "Worked for"
    sleep 1.5

    assert_not page.evaluate_script("window.__ranAgain"), "a finished step showed as running"
  end
end
