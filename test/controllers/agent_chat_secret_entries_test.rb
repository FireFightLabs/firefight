require "test_helper"

class AgentChatSecretEntriesTest < ActionDispatch::IntegrationTest
  ADDRESS = "https://webhooks.northflank.com/workflows/Xq9bNfLm2RtYvWc8KpZaH4sJdE6uGo1i".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @set_secret = github.tools.create!(name: "set_actions_secret", read_only: false, enabled: true)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    row = northflank.integration_environments.create!
    add_webhook = northflank.tools.create!(name: "add_workflow_webhook", read_only: false, enabled: true)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    chat = @conversation.chat_record
    @entry = chat.secret_entries.create!(kind: Chat::SecretEntry::KIND_ENTER, status: Chat::SecretEntry::STATUS_PENDING, tool: @set_secret,
                                         requester: @alice, title: "DEPLOY_HOOK in acme/web", target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK" },
                                         expires_at: 1.hour.from_now)
    @reveal = chat.secret_entries.create!(kind: Chat::SecretEntry::KIND_REVEAL, status: Chat::SecretEntry::STATUS_READY, tool: add_webhook, requester: @alice,
                                          title: "Webhook address of Release, trigger deploy-hook",
                                          reference: Integrations::SecretHandoffs.reference_for(row, "add_workflow_webhook", "firefight/release/deploy-hook"))
    ConversationChannel.stubs(:broadcast_to)
    sign_in(users(:alice), @workspace)
  end

  test "the chat shows the field, and the value typed goes straight to the provider once, then the card says who set it" do
    get agent_chat_url(@conversation), headers: inertia_headers
    card = inertia_props["secretEntries"].find { |each| each["id"] == @entry.id }
    assert_equal [ "Enter the value for DEPLOY_HOOK in acme/web", "enter", nil ], card.values_at("headline", "kind", "blockedReason")
    assert_match(/\AOpen until \d\d:\d\d UTC\.\z/, card["statusLine"])
    refute_includes inertia_props.to_json, "reference"

    Integrations::Packs::Github.any_instance.expects(:fill_secret)
                               .with(environment_row: anything, target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK" }, value: "s3cret")
                               .returns("Set DEPLOY_HOOK in acme/web.")
    post agent_chat_secret_entry_fill_url(@conversation, @entry), params: { secret_value: "s3cret" }

    assert_equal "Set DEPLOY_HOOK in acme/web.", flash[:notice]
    assert_equal [ Chat::SecretEntry::STATUS_SET, @alice ], [ @entry.reload.status, @entry.done_by ]
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: @set_secret.action_key)
    refute_includes invocation.params.to_json, "s3cret"

    post agent_chat_secret_entry_fill_url(@conversation, @entry), params: { secret_value: "again" }
    assert_equal "This value was already set.", flash[:alert]
    assert_equal "[FILTERED]", ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("secret_value" => "x")["secret_value"]
  end

  test "a failed send opens the field again and says why, and a closed field takes nothing" do
    Integrations::Packs::Github.any_instance.stubs(:fill_secret).raises(Integrations::NativePack::Error, "GitHub refused this.")
    post agent_chat_secret_entry_fill_url(@conversation, @entry), params: { secret_value: "s3cret" }
    assert_equal "Nothing was set. GitHub refused this.", flash[:alert]
    assert_equal Chat::SecretEntry::STATUS_PENDING, @entry.reload.status

    @entry.update!(expires_at: 1.minute.ago)
    post agent_chat_secret_entry_fill_url(@conversation, @entry), params: { secret_value: "s3cret" }
    assert_match "This field closed at", flash[:alert]
  end

  test "a credential is revealed live as JSON, never cached, and only to the person the call ran as" do
    Integrations::Packs::Northflank.any_instance.expects(:secret_value).with(environment_row: anything, path: "firefight/release/deploy-hook").returns(ADDRESS)

    post agent_chat_secret_entry_reveal_url(@conversation, @reveal), as: :json
    assert_response :success
    assert_equal ADDRESS, response.parsed_body["value"]
    assert_equal "no-store", response.headers["Cache-Control"]

    @reveal.update!(requester: workspace_memberships(:bob_workspace_one))
    post agent_chat_secret_entry_reveal_url(@conversation, @reveal), as: :json
    assert_response :unprocessable_content
    assert_equal "Only Bob Jones can reveal this, since the call ran as them.", response.parsed_body["error"]
  end
end
