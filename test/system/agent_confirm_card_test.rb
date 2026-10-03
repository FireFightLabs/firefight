require "application_system_test_case"

class AgentConfirmCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @conversation.ask!("clean up the permission sets")
    @chat = @conversation.chat
  end

  test "answering the last question first moves to the open ones, and Send waits for every answer" do
    pause_on("delete_permission_set", "delete_permission_set", "delete_permission_set")
    visit agent_chat_path(@conversation)

    2.times { find("button[aria-label='Next question']").click }
    answer("set_3", "Confirm")
    on_question("set_1")
    assert_button "Continue", disabled: true
    assert_no_button "Send"
    assert_equal [ Chat::APPROVAL_REQUESTED ] * 3, approvals, "nothing is sent while two questions are open"

    answer("set_1", "Cancel")
    answer("set_2", "Confirm")

    assert_decided [ Chat::APPROVAL_DENIED, Chat::APPROVAL_APPROVED, Chat::APPROVAL_APPROVED ]
  end

  test "allowing a tool for the rest of the chat answers every question about it" do
    pause_on("delete_permission_set", "delete_permission_set")
    visit agent_chat_path(@conversation)

    click_button "Allow for the rest of this chat"

    assert_decided [ Chat::APPROVAL_APPROVED ] * 2
    assert @chat.reload.allows_tool?("delete_permission_set")
  end

  private

  def pause_on(*tool_names)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    @ids = tool_names.each_with_index.map do |name, index|
      message.ruby_llm_tool_calls.create!(tool_call_id: "call_#{index + 1}", name: name, arguments: { "slug" => "set_#{index + 1}" }).tool_call_id
    end
    @chat.request_decisions!(@ids)
    @conversation.reply_delivered!
  end

  # The card moves on half a second after a pick, so each answer waits for its question to be the one shown.
  QUESTION = "[style*='opacity: 1']:has(button[aria-pressed])".freeze

  def on_question(slug) = assert_selector(QUESTION, text: slug)

  def answer(slug, option)
    on_question(slug)
    within(find(QUESTION, text: slug)) { click_button option }
  end

  def approvals = @chat.tool_calls.where(tool_call_id: @ids).order(:tool_call_id).pluck(:approval)

  # The card shows Sent only until the server answers and the chat moves on, which can be before a check sees it. What
  # lasts is the decisions saved, so the test waits for those.
  def assert_decided(expected)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "decisions are #{approvals.inspect}" unless approvals == expected
    end
    assert_equal expected, approvals
  end
end
