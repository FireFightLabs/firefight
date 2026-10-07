require "application_system_test_case"

class AgentChatLayoutTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
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
end
