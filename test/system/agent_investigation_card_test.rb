require "application_system_test_case"

class AgentInvestigationCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a run a chat started is a card with its answer, opens over the chat, and offers the incident its answer asks for" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("why is checkout slow")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Mcp::Tools::START_INVESTIGATION, arguments: { "symptom" => "Checkout is slow" })
    conversation.chat.add_message(role: :tool, content: "Started.", tool_call_id: "call_1")
    conversation.note!("It is running. Its answer will come back here.")
    conversation.reply_delivered!
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @member, max_turns: 10, max_spend_cents: 400,
      conversation: conversation, tool_call_id: "call_1", status: Investigation::STATUS_SUCCEEDED,
      started_at: 1.minute.ago, completed_at: Time.current, brief: { Investigation::Brief::KEY_SYMPTOM => "Checkout is slow" }
    )
    run.conclude!(summary: "Checkout writes time out on the orders database, since the 14:02 deploy.", suggest_incident: true)

    visit agent_chat_path(conversation)

    within("section[aria-label='Investigation']") do
      assert_text "Checkout is slow"
      assert_text "Checkout writes time out on the orders database"
      click_button "Open"
    end

    within("[role=dialog]") do
      assert_text "Halon thinks this is hurting users now."
      click_button "Declare incident"
    end
    assert_text "The investigation and its answer go on the new incident's timeline."
    page.save_screenshot(Rails.root.join("tmp/screenshots/chat-investigation-declare.png"))
  end
end
