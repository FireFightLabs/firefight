require "application_system_test_case"

# A change Halon was refused because the person asking holds no pack for it. The card names the pack and the admins, and
# Ask an admin sends them one request.
class AgentPackRefusalCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    @adapter = stub_everything(post_pack_request_to_user: { channel_id: "D1", message_id: "1.1" })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    restart = faylee.tools.create!(name: "restart_service", read_only: false, enabled: true)
    sign_in(users(:bob), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @conversation.ask!("Restart Faylee's web service")
    Conversation::Turn.new(@conversation, asker: @bob).pack_refused!(restart.action_key, "call_1")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT,
                                        content: "You do not have permission to restart services on Faylee. It needs the Faylee (Northflank): changes pack, and the workspace admin is Alice Smith.")
    @conversation.reply_delivered!
  end

  test "the refusal names the pack and the admins, and Ask an admin asks once with a toast" do
    visit agent_chat_path(@conversation)

    assert_text "Bob Jones does not have permission to make this change."
    assert_text "It needs the Faylee (Northflank): changes pack. The workspace admin is Alice Smith."
    page.save_screenshot(Rails.root.join("tmp/screenshots/pack-refusal-card.png"))
    click_button "Ask an admin"

    assert_text "Asked Alice Smith for Faylee (Northflank): changes."
    assert_text "Asked the admins at"
    assert_no_button "Ask an admin"
    page.save_screenshot(Rails.root.join("tmp/screenshots/pack-refusal-asked.png"))
  end
end
