require "application_system_test_case"

class WorkflowHalonChatTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: @alice,
                    payload: { "step" => { "id" => "wait", "name" => "wait_a_bit", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 1 } } })
  end

  test "a question asked beside the canvas starts a chat about the workflow and shows in the panel" do
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    click_button "Ask Halon"
    within("aside[aria-label='Halon']") do
      assert_text "What it changes shows on the canvas as a suggestion you accept or dismiss."
      click_button "What does this workflow do, step by step?"
      find("textarea").send_keys(:enter)
      assert_text "What does this workflow do, step by step?"
      assert_selector "a[aria-label='Open the full chat']"
    end

    chat = Conversation.beside(@workflow, workspace_memberships(:bob_workspace_one))
    assert_equal @workflow, chat.subject
    within("aside[aria-label='Halon']") { assert_selector "a[aria-label='Open the full chat'][href='#{agent_chat_path(chat)}']" }
  end

  test "what Halon proposed from the chat shows on the canvas to accept" do
    chat = Conversation::Asking.start_personal(workspace: @workspace, member: @alice, question: "Add a second wait.", subject: @workflow)
    @workflow.reload.draft.publish!(by: @alice)
    @workflow.reload.propose_from_chat!(
      [ { "operation" => Workflow::Edit::OPERATION_ADD_STEP,
          "payload" => { "step" => { "id" => "then", "name" => "then_wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 2 } } } } ],
      reason: "Waits once more.", chat: chat.chat_record
    )
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    assert_text "1 suggestion from Halon"
    assert_text "Waits once more."
    click_button "Ask Halon"
    within("aside[aria-label='Halon']") { assert_text "Add a second wait." }
  end
end
