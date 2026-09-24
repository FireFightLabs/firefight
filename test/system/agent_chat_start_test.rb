require "application_system_test_case"

class AgentChatStartTest < ApplicationSystemTestCase
  PHONE = [ 390, 844 ].freeze
  DESKTOP = [ 1400, 1400 ].freeze

  setup do
    workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
  end

  # The browser is shared across tests, so a phone sized window is put back before the next test.
  teardown do
    page.driver.browser.manage.window.resize_to(*DESKTOP)
  end

  test "a new chat holds the composer in the middle, and an example question fills it" do
    visit agent_chats_path

    assert_text "What do you want to know?"
    assert_no_selector "section.agent-thread-open"

    click_button "What changed before an incident?"

    assert_equal "What changed before @", prompt.value
    assert_text "Type to search incidents"
  end

  test "the first question opens the chat and moves the composer to the foot" do
    visit agent_chats_path

    prompt.send_keys("Which incidents are open right now?", :enter)

    assert_selector "section.agent-thread-open"
    assert_text "Which incidents are open right now?"
    assert_no_text "What do you want to know?"
  end

  # Seen through a slow connection. The composer emptied and nothing showed until the server answered, which read as a reload.
  test "the question and the working state show the moment it is sent, before the server answers" do
    conversation = Conversation.start_personal!(workspace: workspaces(:slack_workspace_one), member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("what is open")
    conversation.note!("Nothing is open.")
    conversation.reply_delivered!
    Conversation::Asking.stubs(:ask).with { sleep 2 }.returns(nil)
    visit agent_chat_path(conversation)

    prompt.send_keys("and now?", :enter)

    assert_text "and now?", wait: 1
    assert_text "Working", wait: 1
  end

  test "on a phone, New chat shows the start page and All chats goes back to the list" do
    page.driver.browser.manage.window.resize_to(*PHONE)
    visit agent_chats_path

    assert_text "No chats yet."
    assert_no_text "What do you want to know?"

    click_button "New chat"

    assert_text "What do you want to know?"
    assert_no_text "No chats yet."

    click_button "All chats"

    assert_text "No chats yet."
    assert_no_text "What do you want to know?"
  end

  private

  def prompt
    find("textarea[aria-label='Prompt']")
  end
end
