require "test_helper"

# A token Firefight mints is shown once to the person it was made for, and never to a model: Halon gets a card in its
# chat, an outside agent's person gets a message in Slack only they see, and the answer either reads carries a
# placeholder.
class TokenHandoffTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "Firefight's own token shape is taken out of anything a model or a log reads" do
    token = ApiKey.generate_token

    assert_equal "Use [REDACTED:firefight_token] here", Chat::SecretFree.redacted("Use #{token} here")
    assert_includes IncidentTranscriptMessage::Scrubbing::SECRET_PATTERNS.keys, :firefight_token
  end

  test "Halon making an agent hands the model a placeholder and the person a card that shows the token once" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    conversation.chat_record
    turn = Conversation::Turn.new(conversation, asker: @admin)
    tool = Chat::Tools::Firefight.new(turn, Mcp::Tools::UpsertAgent, Ability::Action.system!("permissions.create"))

    said = tool.call(name: "Deployer")

    assert_no_match(/ff_[A-Za-z0-9]{20,}/, said, "the model never reads the token")
    entry = conversation.chat.secret_entries.sole
    assert_equal Chat::SecretEntry::KIND_TOKEN, entry.kind
    assert_equal @admin, entry.requester
    agent = @workspace.agents.find_by!(slug: "deployer")
    assert_equal agent.live_api_keys.sole, entry.api_key
    assert_match "card under this step", said
    assert conversation.chat.messages.where("content LIKE ?", "%ff_%").none? { |message| message.content.match?(/ff_[A-Za-z0-9]{20,}/) }

    assert_equal "Only Alice Smith can reveal this, since the call ran as them.", SecretEntryService.reveal(entry, by: @bob).words
    shown = SecretEntryService.reveal(entry, by: @admin)
    assert_equal agent, ApiKey.authenticate(shown.value).principal
    assert_equal Chat::SecretEntry::STATUS_SET, entry.reload.status
    assert_not entry.open?
    assert_nil SecretEntryService.reveal(entry, by: @admin).value, "it is shown once"
  end

  test "an outside agent minting a token gets a placeholder, and the person behind it is shown it in Slack alone" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_token_once).with do |user_id:, title:, token:|
      user_id == @admin.platform_user_id && title == "Deployer token" && ApiKey.authenticate(token)&.agent&.slug == "deployer"
    end.returns({ success: true })

    response = call_approved_by_a_person(tool: Mcp::Tools::UpsertAgent, server_context: { workspace: @workspace, principal: @admin }, args: { name: "Deployer" })

    assert_not response.error?
    assert_no_match(/ff_[A-Za-z0-9]{20,}/, Mcp::ToolDispatcher.text_of(response))
    assert_match "Shown once to Alice Smith in a direct message", response.structured_content[:token]
  end

  test "an outside agent cannot mint a token for someone Firefight cannot reach in Slack, and nothing is made" do
    @workspace.update_columns(platform: nil)

    response = call_approved_by_a_person(tool: Mcp::Tools::UpsertApiKey, server_context: { workspace: @workspace, principal: @admin }, args: { name: "CI" })

    assert response.error?
    assert_match "Create it in Firefight", Mcp::ToolDispatcher.text_of(response)
    assert_not @workspace.api_keys.exists?(name: "CI")
  end

  test "a token Slack could not show is revoked at once, so no unseen token stays live" do
    Slack::WorkspaceAdapter.any_instance.stubs(:post_token_once).raises(AdapterError, "channel_not_found")
    agent = @workspace.agents.create!(name: "Deployer", slug: "deployer")

    response = call_approved_by_a_person(tool: Mcp::Tools::RotateAgentToken, server_context: { workspace: @workspace, principal: @admin }, args: { slug: "deployer" })

    assert response.error?
    assert_match "revoked", Mcp::ToolDispatcher.text_of(response)
    assert_empty agent.reload.live_api_keys
  end

  test "a token whose handoff breaks for any reason is revoked, so no unseen token stays live" do
    agent = @workspace.agents.create!(name: "Deployer", slug: "deployer")
    broken = ->(_token) { raise ActiveRecord::RecordInvalid }

    assert_raises(ActiveRecord::RecordInvalid) do
      Mcp::ToolDispatcher.run(tool: Mcp::Tools::RotateAgentToken, workspace: @workspace, principal: @admin, args: { slug: "deployer" }, hand_token: broken)
    end
    assert_empty agent.reload.live_api_keys
  end

  test "a card whose token could not be minted stays ready for another try" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    agent = @workspace.agents.create!(name: "Deployer", slug: "deployer")
    key, = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, agent: agent, name: "Deployer token")
    entry = Chat::SecretEntry.record_token!(chat: conversation.chat_record, tool_call_id: "call_1", api_key: key, requester: @admin)
    ApiKey.any_instance.stubs(:reissue_token!).raises(ActiveRecord::StatementInvalid)

    assert_raises(ActiveRecord::StatementInvalid) { SecretEntryService.reveal(entry, by: @admin) }
    assert_equal Chat::SecretEntry::STATUS_READY, entry.reload.status
  end
end
