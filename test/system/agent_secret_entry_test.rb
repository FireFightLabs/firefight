require "application_system_test_case"

class AgentSecretEntryTest < ApplicationSystemTestCase
  ADDRESS = "https://webhooks.northflank.com/workflows/Xq9bNfLm2RtYvWc8KpZaH4sJdE6uGo1i".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    ConversationChannel.stubs(:broadcast_to)
    sign_in(users(:alice), @workspace)
  end

  test "a value is typed into a password field under the step, sent once, and the card says who set it" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    tool = github.tools.create!(name: "set_actions_secret", read_only: false, enabled: true)
    conversation = chat_with_answer("Set DEPLOY_HOOK_URL in acme/web. Type its value in the field below.")
    conversation.chat.secret_entries.create!(kind: Chat::SecretEntry::KIND_ENTER, status: Chat::SecretEntry::STATUS_PENDING, tool: tool, requester: @alice,
                                             title: "DEPLOY_HOOK_URL in acme/web", target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK_URL" },
                                             expires_at: 1.hour.from_now)
    Integrations::Packs::Github.any_instance.expects(:fill_secret).with(environment_row: anything, target: anything, value: "s3cret-value")
                               .returns("Set DEPLOY_HOOK_URL in acme/web.")

    visit agent_chat_path(conversation)
    within("section[aria-label='Enter the value for DEPLOY_HOOK_URL in acme/web']") do
      assert_text "Halon never sees it"
      click_on "Enter value"
    end
    within("[role='dialog']") do
      assert_field "Value", type: "password"
      fill_in "Value", with: "s3cret-value"
      page.save_screenshot(Rails.root.join("tmp/screenshots/agent-secret-entry-dialog.png"))
      click_on "Set value"
    end

    assert_text "Set by Alice Smith at"
    assert_selector "section[aria-label='DEPLOY_HOOK_URL in acme/web']"
    assert_no_button "Enter value"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-secret-entry-set.png"))
  end

  test "a credential a tool made is revealed in a dialog with a copy button" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    row = northflank.integration_environments.create!
    tool = northflank.tools.create!(name: "add_workflow_webhook", read_only: false, enabled: true)
    conversation = chat_with_answer("Added webhook trigger release-webhook to the Release workflow. Reveal its address below.")
    conversation.chat.secret_entries.create!(kind: Chat::SecretEntry::KIND_REVEAL, status: Chat::SecretEntry::STATUS_READY, tool: tool, requester: @alice,
                                             title: "Webhook address of Release, trigger release-webhook",
                                             reference: Integrations::SecretHandoffs.reference_for(row, "add_workflow_webhook", "firefight/release/release-webhook"))
    Integrations::Packs::Northflank.any_instance.stubs(:secret_value).returns(ADDRESS)

    visit agent_chat_path(conversation)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-secret-reveal-card.png"))
    click_on "Reveal"

    within("[role='dialog']") do
      assert_text ADDRESS
      assert_button "Copy"
      page.save_screenshot(Rails.root.join("tmp/screenshots/agent-secret-reveal-dialog.png"))
    end
  end

  private

  def chat_with_answer(answer)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    conversation.ask!("Wire the release webhook")
    conversation.note!(answer)
    conversation.reply_delivered!
    conversation
  end
end
