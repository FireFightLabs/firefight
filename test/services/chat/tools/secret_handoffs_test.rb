require "test_helper"

# Seen in a real chat, Halon set up a release webhook between two providers and the webhook's address, which works as a
# password, was meant to pass through the chat. A secret is typed by the person in Firefight, or read by Firefight from
# the connection that made it, and Halon only ever names it.
class Chat::Tools::SecretHandoffsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ADDRESS = "https://webhooks.northflank.com/workflows/Xq9bNfLm2RtYvWc8KpZaH4sJdE6uGo1i".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat = @conversation.chat_record

    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @set_secret = github.tools.create!(name: "set_actions_secret", description: "Sets a secret", enabled: true, read_only: false,
                                       params_schema: Integrations::Packs::Github.tool_definitions.find { |tool| tool.name == "set_actions_secret" }.params_schema)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    @northflank_row = @northflank.integration_environments.create!
    @add_webhook = @northflank.tools.create!(name: "add_workflow_webhook", description: "Adds a webhook", enabled: true, read_only: false,
                                             params_schema: { "type" => "object", "properties" => {} })
    @reference = Integrations::SecretHandoffs.reference_for(@northflank_row, "add_workflow_webhook", "firefight/release/deploy-hook")

    Integrations::GithubApp.stubs(:installation_token).returns("ghs_token")
    Integrations::GithubApp.stubs(:get).with("/repos/acme/web/actions/secrets/public-key", token: "ghs_token")
                           .returns("key_id" => "1", "key" => Base64.strict_encode64("k" * 32))
    ConversationChannel.stubs(:broadcast_to)
  end

  test "without value_from the person gets a card to type the value, and Halon is told where it is" do
    Integrations::GithubApp.expects(:write).never

    said = nil
    assert_enqueued_with(job: SecretEntryJob) { said = call(@set_secret, repo: "acme/web", name: "DEPLOY_HOOK") }

    entry = @chat.secret_entries.sole
    assert_equal [ Chat::SecretEntry::KIND_ENTER, Chat::SecretEntry::STATUS_PENDING, @alice, "call_1" ], [ entry.kind, entry.status, entry.requester, entry.tool_call_id ]
    assert_equal({ "repo" => "acme/web", "name" => "DEPLOY_HOOK" }, entry.target)
    assert_includes said, "Alice Smith types it in the secure field under this step"
    assert_includes said, "Never ask for the value in the chat"
  end

  test "value_from has Firefight read the value where the reference says and send it, never showing it" do
    Integrations::Packs::Northflank.any_instance.expects(:secret_value).with(environment_row: @northflank_row, path: "firefight/release/deploy-hook").returns(ADDRESS)
    Integrations::Packs::Github.any_instance.expects(:fill_secret)
                               .with(environment_row: anything, target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK" }, value: ADDRESS)
                               .returns("Set DEPLOY_HOOK in acme/web.")

    said = call(@set_secret, repo: "acme/web", name: "DEPLOY_HOOK", value_from: @reference)

    assert_includes said, "Set DEPLOY_HOOK in acme/web. The value came from #{@reference} and was never shown."
    refute_includes said, ADDRESS
    assert_empty @chat.secret_entries
    read = Ability::Invocation.find_by!(workspace: @workspace, action_key: @add_webhook.action_key)
    assert_equal({ "reference" => @reference }, read.params)
    refute_includes Ability::Invocation.where(workspace: @workspace).pluck(:params).to_json, ADDRESS
  end

  test "a reference the person may not read is refused in words, and nothing is set" do
    bob = workspace_memberships(:bob_workspace_one)
    Ability::Grant.create!(workspace: @workspace, principal: bob, action: @set_secret.reload.ability_action)
    turn = Conversation::Turn.new(@conversation, asker: bob)
    Integrations::Packs::Github.any_instance.expects(:fill_secret).never

    said = call(@set_secret, turn: turn, repo: "acme/web", name: "DEPLOY_HOOK", value_from: @reference)

    assert_includes said, "Bob Jones may not use Northflank's add_workflow_webhook, so what it made cannot be read for them."
  end

  private

  def call(tool, id: "call_1", turn: @turn, **arguments)
    llm_call = RubyLLM::ToolCall.new(id: id, name: tool.model_facing_name, arguments: arguments.stringify_keys)
    @chat.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { id => llm_call }))
    Chat::Tools::Connection.new(turn, tool).call(tool_call: llm_call, **arguments)
  end
end
