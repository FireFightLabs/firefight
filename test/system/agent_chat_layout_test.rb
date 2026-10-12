require "application_system_test_case"

class AgentChatLayoutTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the chat sits under the page header's own edge, with no second line of its own" do
    visit agent_chats_path

    assert_selector ".agent-chat"
    assert_equal "0px", evaluate_script("getComputedStyle(document.querySelector('.agent-chat')).borderTopWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-header-edge.png"))
  end

  test "the question box grows with what is typed, up to a few lines, then scrolls" do
    visit agent_chats_path

    prompt = find("textarea[aria-label='Prompt']")
    single = prompt.evaluate_script("this.offsetHeight")
    prompt.send_keys("First line", [ :shift, :enter ], "Second line", [ :shift, :enter ], "Third line")
    grown = prompt.evaluate_script("this.offsetHeight")
    assert_operator grown, :>, single

    prompt.send_keys(*Array.new(8) { [ [ :shift, :enter ], "More" ] }.flatten(1))
    assert_equal "auto", prompt.evaluate_script("getComputedStyle(this).overflowY")
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-prompt-grows.png"))
  end

  test "on a phone the question box has its own row above the controls, and the model menu stays on screen" do
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("what changed today")
    page.current_window.resize_to(390, 844)
    visit agent_chat_path(conversation)

    prompt = find("textarea[placeholder='Add something while Halon works']")
    picker = find("button[aria-label^='Model:']")
    stop = find("button[aria-label='Stop']")
    assert_operator picker.rect.y, :>=, prompt.rect.y + prompt.rect.height
    assert_equal picker.rect.y + picker.rect.height, stop.rect.y + stop.rect.height
    assert_operator stop.rect.x, :>, picker.rect.x + picker.rect.width

    click_on "All chats"
    find("button[aria-label='New chat']").click
    prompt = find("textarea[placeholder='Ask the agent, or @ an incident']")
    picker = find("button[aria-label^='Model:']")
    assert_operator picker.rect.y, :>=, prompt.rect.y + prompt.rect.height
    picker.click
    menu = find("[role=menu]")
    chat = find(".agent-chat")
    assert_operator menu.rect.y, :>=, chat.rect.y
    assert_operator menu.rect.y + menu.rect.height, :<=, chat.rect.y + chat.rect.height
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-phone-composer.png"))
  end
end
