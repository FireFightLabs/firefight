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
end
