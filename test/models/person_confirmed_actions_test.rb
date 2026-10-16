require "test_helper"

# Who may do what, the credentials that carry it, the approvals that decide it and where events are sent are changed only
# with a person's say. Halon asks on its confirmation card every time, and a call made with a token or by a machine
# waits for a person to approve it.
class PersonConfirmedActionsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
  end

  test "changes to permissions, credentials, approvals and webhooks ask a person, and reading them does not" do
    %w[permissions.create permissions.update permissions.delete api_keys.create api_keys.update approvals.update webhooks.create webhooks.delete].each do |key|
      assert Ability::Action.system!(key).asks_a_person?, "#{key} asks a person"
    end
    %w[permissions.read approvals.read webhooks.read incidents.update catalog.create].each do |key|
      assert_not Ability::Action.system!(key).asks_a_person?, "#{key} does not"
    end
    assert Mcp::Tools::GrantAbility.asks_a_person?
    assert Mcp::Tools::UpsertApiKey.asks_a_person?
    assert Mcp::Tools::UpsertOutboundWebhook.asks_a_person?
    assert Mcp::Tools::ApproveApproval.asks_a_person?
    assert_not Mcp::Tools::ListAbilities.asks_a_person?
    assert_not Mcp::Tools::TestOutboundWebhook.asks_a_person?, "a test delivery changes nothing"
  end

  test "Halon always asks before such a change, even when the chat allowed the tool or a plan approved it ahead" do
    conversation = @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: @admin, max_turns: 10, max_spend_cents: 40)
    grant = Ability::Action.system!("permissions.create")
    turn = Conversation::Turn.new(conversation, asker: @admin)

    assert turn.confirms?(grant, allowed: true, tool_name: Mcp::Tools::GRANT_ABILITY, asks_a_person: true)
    turn.instance_variable_set(:@approved_tools, [ Mcp::Tools::GRANT_ABILITY ])
    assert turn.confirms?(grant, tool_name: Mcp::Tools::GRANT_ABILITY, asks_a_person: true)
    tool = Chat::Tools::Firefight.new(turn, Mcp::Tools::GrantAbility, grant)
    assert tool.requires_approval?, "Halon's own tool asks"
    assert_not turn.confirms?(Ability::Action.system!("catalog.create"), allowed: true, tool_name: "upsert_catalog_entry")
  end

  test "the card for such a change never offers Allow for the rest of this chat, and a stored allow never answers it" do
    conversation = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C_INCIDENT", thread_id: "1700000000.000100", started_by: @admin, max_turns: 10, max_spend_cents: 40
    )
    chat = conversation.chat_record
    message = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: "call_grant", name: Mcp::Tools::GRANT_ABILITY, arguments: { "principal" => "bob" })
    chat.request_decisions!([ "call_grant" ])
    call.reload

    assert_not Chat::Tools.confirmation(call).allowable?
    Conversation::Confirming.decide(conversation, [ { tool_call_id: "call_grant", approved: true, for_chat: true } ], by: @admin)
    assert_not chat.reload.allows_tool?(Mcp::Tools::GRANT_ABILITY), "approving it never allows it for the rest of the chat"

    later = message.ruby_llm_tool_calls.create!(tool_call_id: "call_grant_again", name: Mcp::Tools::GRANT_ABILITY, arguments: { "principal" => "carol" })
    chat.request_decisions!([ "call_grant_again" ])
    chat.allow_tool!(Mcp::Tools::GRANT_ABILITY)
    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      Conversation::Confirming.decide(conversation, [], by: @admin)
    end
    assert_equal Chat::APPROVAL_REQUESTED, later.reload.approval, "an allow kept from before never answers it"
  end

  test "a call made with a token waits for a person to approve it, whoever holds the token" do
    action_key = "permissions.create"

    error = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: @admin, action_key: action_key, workspace: @workspace, params: { "principal" => "bob" },
                                context: { source: AbilityGateway::SOURCE_MCP, asks_a_person: true }) { :ran }
    end
    assert_equal action_key, error.approval.action_key
    assert_equal WorkspaceMembership.roles[:admin], error.approval.required_role

    assert_equal :ran, AbilityGateway.authorize!(principal: @admin, action_key: action_key, workspace: @workspace, params: {},
                                                 context: { source: AbilityGateway::SOURCE_WEB, asks_a_person: true }) { :ran }
    assert_equal :ran, AbilityGateway.authorize!(principal: @admin, action_key: action_key, workspace: @workspace, params: {},
                                                 context: { source: AbilityGateway::SOURCE_CONVERSATION, asks_a_person: true }) { :ran }
  end

  test "a machine with a grant still waits for a person, wherever it calls from" do
    agent = @workspace.agents.create!(name: "Deployer", slug: "deployer")
    Ability::Grant.grant!(workspace: @workspace, principal: agent, target: { action: Ability::Action.system!("webhooks.create") })

    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: agent, action_key: "webhooks.create", workspace: @workspace, params: { "url" => "https://hooks.example" },
                                context: { source: AbilityGateway::SOURCE_WORKFLOW, asks_a_person: true }) { :ran }
    end
  end

  test "an admin's own token over MCP still waits for a person before it grants anything" do
    bob = workspace_memberships(:bob_workspace_one)
    response = Mcp::ToolDispatcher.call(
      tool: Mcp::Tools::GrantAbility, server_context: { workspace: @workspace, principal: @admin },
      args: { principal_kind: "user", principal_id: bob.user_id, ability: "incidents.create" }
    )

    assert response.error?
    assert_match(/Approval required/, Mcp::ToolDispatcher.text_of(response))
    assert_not @workspace.ability_grants.exists?(principal: bob), "nothing is granted until a person approves"
  end

  test "once a person approves the held call, the same call runs once" do
    params = { "principal" => "bob" }
    held = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: @admin, action_key: "permissions.create", workspace: @workspace, params: params,
                                context: { source: AbilityGateway::SOURCE_MCP, asks_a_person: true }) { :ran }
    end.approval
    held.update!(status: Ability::Approval::STATUS_APPROVED, resolved_at: Time.current)

    assert_equal :ran, AbilityGateway.authorize!(principal: @admin, action_key: "permissions.create", workspace: @workspace, params: params,
                                                 context: { source: AbilityGateway::SOURCE_MCP, asks_a_person: true, approval_id: held.id }) { :ran }
  end
end
