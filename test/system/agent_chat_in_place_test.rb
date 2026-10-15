require "application_system_test_case"

# Seen live: pressing Enter read the whole open chat back, every card under it included, which took 1.4 seconds and read
# as the page reloading. Each change made from a chat shows at once, stays on the page, and reads back only what it changed.
class AgentChatInPlaceTest < ApplicationSystemTestCase
  include HandbookTestHelper

  THREAD = "section.agent-thread-open".freeze
  HANDBOOK_CARD = "section[aria-label='Handbook edit']".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("what is open")
    @conversation.note!("Nothing is open.")
    @conversation.reply_delivered!
  end

  test "a message sent shows at once and Halon starts working, with the chat list and cards never read again" do
    visit agent_chat_path(@conversation)
    assert_text "Nothing is open."
    watch_page

    prompt.send_keys("and now?", :enter)

    assert_selector THREAD, text: "and now?"
    assert_text "Working"
    assert_selector "[aria-label='Prompt'][placeholder='Add something while Halon works']"
    assert_stayed_in_place(only: AgentChatsController::ASKED_PROPS)
    assert_equal "and now?", @conversation.chat.reload.messages.where(role: Chat::Message::ROLE_USER).order(:created_at).last.content
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-sent-in-place.png"))
  end

  test "something added while Halon works waits for its next step, on the same page" do
    @conversation.ask!("and the worker?")
    @conversation.update!(answer_owed_since: 5.seconds.ago)
    visit agent_chat_path(@conversation)
    assert_selector "[aria-label='Prompt'][placeholder='Add something while Halon works']"
    watch_page

    prompt.send_keys("check the queue too", :enter)

    assert_selector THREAD, text: "check the queue too"
    assert_stayed_in_place(only: AgentChatsController::ASKED_PROPS)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-waiting-in-place.png"))
  end

  test "a handbook edit is accepted, edited first or dismissed from its card on the same page" do
    page = handbook_page!(@workspace, "How web deploys", "Web deploys from main.")
    accepted = Chat::HandbookProposal.propose!(@conversation, page: page, text: "Web deploys from the release branch.", evidence: "The deploy log of web.")
    visit agent_chat_path(@conversation)
    watch_page

    within(HANDBOOK_CARD) { click_button "Accept edit" }

    assert_toast "How web deploys"
    assert_selector HANDBOOK_CARD, text: "The page now says"
    assert_stayed_in_place(only: AgentChatsController::PROP_HANDBOOK_PROPOSALS)
    assert accepted.reload.decided_at

    edited = Chat::HandbookProposal.propose!(@conversation, page: page.reload, text: "Web deploys from the release branch at noon.",
                                                            evidence: "The deploy log of web again.")
    dismissed = Chat::HandbookProposal.propose!(@conversation, title: "How api deploys", text: "Api deploys from main.", evidence: "The deploy log of api.")
    visit agent_chat_path(@conversation)
    watch_page

    within(HANDBOOK_CARD, text: "The deploy log of web again.") { click_button "Edit first" }
    click_button "Accept with edit"
    assert_toast "How web deploys"
    within(HANDBOOK_CARD, text: "The deploy log of api.") { click_button "Dismiss" }
    assert_toast "The proposed"

    assert_stayed_in_place(only: AgentChatsController::PROP_HANDBOOK_PROPOSALS)
    assert edited.reload.decided_at
    assert dismissed.reload.decided_at
  end

  test "asking Halon beside a workflow's canvas shows the question at once and reads back only the chat" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    visit workflow_path(workflow)
    click_button "Ask Halon"
    watch_page

    within("aside[aria-label='Halon']") { find("[aria-label='Prompt']").send_keys("What does it do?", :enter) }

    assert_selector "aside[aria-label='Halon']", text: "What does it do?"
    assert_selector "aside[aria-label='Halon'] [aria-label='Prompt'][placeholder='Add something while Halon works']"
    assert_stayed_in_place(only: WorkflowCanvasController::CHAT_PROPS)
    page.save_screenshot(Rails.root.join("tmp/screenshots/workflow-chat-sent-in-place.png"))
  end

  private

  def prompt = find("[aria-label='Prompt']")
end
