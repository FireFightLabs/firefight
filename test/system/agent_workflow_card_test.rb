require "application_system_test_case"

# A workflow Halon made in a dashboard chat, such as "in 30 minutes check web": its card after the answer that made it,
# with when it runs, Run now and Cancel, Cancel asking first, each confirmed with a toast.
class AgentWorkflowCardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:unavailable_reason).returns(nil)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("In 30 minutes check web and tell me how it is.")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "I made Check web. It runs in 30 minutes and tells you here.")
    @conversation.reply_delivered!
    @workflow = Workflow::Authoring.create!(workspace: @workspace, by: @alice, halon: true, reason: "Alice asked for it.", origin_conversation: @conversation,
                                            spec: { template: "check_later", params: { resource: "web", in_minutes: 30, reply_in_chat: true } })
    WorkflowPublishService.new(@workflow).publish!(@workflow.draft, by: @alice)
    Workflow::Run.any_instance.stubs(:may_move?).returns(false)
  end

  test "the card says when it runs, Run now starts it and Cancel asks first, each with a toast" do
    visit agent_chat_path(@conversation)

    assert_text "Check web"
    assert_text "Once on"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-workflow-card.png").to_s)

    click_button "Run now"
    assert_toast "Check web is running."
    assert_equal 1, @workflow.runs.count

    click_button "Cancel"
    click_button "Cancel workflow"
    assert_toast "Check web was cancelled. It will not run."
    assert_not @workflow.reload.enabled?
    assert_no_button "Cancel"
  end

  test "why a button cannot be pressed is said on that button, not under the others" do
    bobs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))
    bobs.ask!("Run Check web.")
    bobs.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "Here it is.")
    bobs.reply_delivered!
    @workflow.update!(origin_conversation: bobs)
    sign_in(users(:bob), @workspace)

    visit agent_chat_path(bobs)

    assert_button "Run now", disabled: false
    assert_button "Cancel", disabled: true
    assert_no_text "can stop Check web"
    find("span", text: "Cancel", match: :first).hover
    assert_text "Only Alice Smith or a workspace admin can stop Check web."
  end

  test "a workspace without workflows shows no card" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    visit agent_chat_path(@conversation)

    assert_text "I made Check web."
    assert_no_selector "section[aria-label=Workflow]"
  end
end
