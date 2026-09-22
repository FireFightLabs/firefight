require "application_system_test_case"

class AgentChatStartTest < ApplicationSystemTestCase
  setup do
    workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
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

  private

  def prompt
    find("textarea[aria-label='Prompt']")
  end
end
