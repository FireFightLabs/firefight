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
end
