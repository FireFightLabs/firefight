require "application_system_test_case"

# A temporary change no fixed call puts back says Halon asks in the chat to put it back, and once Halon was asked it says
# the change stays in place until that call runs, with Undo now alone to ask again.
class AgentTemporaryChangeCardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    posthog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "posthog", name: "PostHog", slug: "posthog",
                                              settings: { "server_url" => "https://mcp.posthog.com/mcp?mode=tools" })
    posthog.integration_environments.create!
    @disable = posthog.tools.create!(name: "feature_flag_disable", description: "Disable", enabled: true, read_only: false, params_schema: { "type" => "object" })
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("Turn new-checkout off for an hour")
    @chat = @conversation.chat
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "I turned new-checkout off.")
    @conversation.reply_delivered!
  end

  test "while it runs it says Halon is asked to put it back, and once asked it offers Undo now alone" do
    mitigation = Chat::Mitigation.create!(
      chat: @chat, workspace: @workspace, asker: @alice, tool_call_id: "call_1", tool_name: @disable.model_facing_name, action_key: @disable.action_key,
      arguments: {}, intent: "Turn new-checkout off", duration_minutes: 60, status: Chat::Mitigation::STATUS_ACTIVE, started_at: Time.current,
      expires_at: 1.hour.from_now, undo_state: Chat::Mitigation::UNDO_IN_CHAT, undo_note: Chat::Mitigation::IN_CHAT_NOTE
    )

    visit agent_chat_path(@conversation)
    within("[aria-label='Temporary change']") do
      assert_text "Halon asks in this chat to put it back at"
      assert_button "Keep it"
      click_button "Undo now"
    end
    within("[role=dialog]") { assert_text "Halon is asked in this chat to put back what this changed" }
    within("[role=dialog]") { click_button "Cancel" }

    mitigation.update_columns(status: Chat::Mitigation::STATUS_UNDO_ASKED, claimed_at: Time.current)
    visit agent_chat_path(@conversation)
    within("[aria-label='Temporary change']") do
      assert_text "Halon was asked in this chat to put it back. It stays in place until that call runs."
      assert_no_button "Keep it"
      assert_no_button "One more hour"
      assert_button "Undo now"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/temporary-change-asked.png").to_s)
  end
end
