require "application_system_test_case"

# A change Halon made without asking sits in the chat where it ran, saying why nobody was asked, with Undo now where
# something puts it back and none where nothing does.
class AgentMadeChangeCardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(credentials: { token: "x" }.to_json)
    @label = github.tools.create!(name: "label_issue", description: "Label", read_only: false, enabled: true, params_schema: { "type" => "object" })
    @tests = github.tools.create!(name: "run_tests", description: "Tests", read_only: false, enabled: true, params_schema: { "type" => "object" })
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("Label issue 12 as a bug and run the tests")
    @chat = @conversation.chat
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "I labelled issue 12 as a bug and ran the tests, which passed.")
    @conversation.reply_delivered!
  end

  test "a safe change says why it was not asked and offers Undo now, and one nothing puts back offers none" do
    made!(@label, "call_label", "Label issue 12 as a bug", Chat::Mitigation::UNDO_NONE)
    made!(@tests, "call_tests", "Run the tests on main", Chat::Mitigation::UNDO_NO_INVERSE)

    visit agent_chat_path(@conversation)

    within("[aria-label='Change made without asking']", text: "Label issue 12 as a bug") do
      assert_text "Halon made it without asking, since it is a safe change."
      assert_button "Undo now"
    end
    within("[aria-label='Change made without asking']", text: "Run the tests on main") do
      assert_text "Nothing puts this back as it was, so there is no Undo."
      assert_no_button "Undo now"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/made-without-asking.png").to_s)

    within("[aria-label='Change made without asking']", text: "Label issue 12 as a bug") { click_button "Undo now" }
    within("[role=dialog]") { click_button "Undo now" }

    assert_toast "Undoing Label issue on GitHub."
    assert_equal Chat::Mitigation::STATUS_UNDOING, Chat::Mitigation.for_call(@chat, "call_label").status
    assert_enqueued_with(job: MitigationUndoRunJob)
  end

  private

  def made!(tool, call_id, title, undo_state)
    Chat::Mitigation.create!(chat: @chat, workspace: @workspace, asker: @alice, tool_call_id: call_id, tool_name: tool.model_facing_name,
                             action_key: tool.action_key, arguments: {}, intent: title, target: "GitHub", status: Chat::Mitigation::STATUS_MADE,
                             started_at: Time.current, told_at: Time.current, undo_state: undo_state, unasked_reason: Ability::Invocation::UNASKED_SAFE)
  end
end
