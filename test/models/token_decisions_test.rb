require "test_helper"

# A token never decides what a token asked for, and never changes the rules that hold calls: those are a person's, in a
# session of their own.
class TokenDecisionsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Admin")
  end

  test "a request made with a token is never approved with a token, and a person in a session approves it" do
    request = approval(source: AbilityGateway::SOURCE_MCP)

    error = assert_raises(Ability::Approval::NotAllowed) { request.approve!(by: @admin, with_token: true) }
    assert_equal Ability::Approval::APPROVE_WITH_TOKEN, error.message
    assert request.reload.pending?

    request.approve!(by: @admin)
    assert request.reload.approved?
  end

  test "a request an agent made counts as a token's, wherever it came from" do
    agent = @workspace.agents.create!(name: "Deployer", slug: "deployer")
    request = approval(source: AbilityGateway::SOURCE_WORKFLOW, principal: agent)

    assert_equal Ability::Approval::APPROVE_WITH_TOKEN, request.approve_with_token_blocked_reason
    assert_nil approval(source: AbilityGateway::SOURCE_WEB).approve_with_token_blocked_reason, "a person's own request follows the rule as before"
  end

  test "the API refuses to approve a token's request with a token, and says why" do
    request = approval(source: AbilityGateway::SOURCE_API)

    post approve_api_v1_approval_url(request), headers: auth(@admin_token), as: :json

    assert_response :unprocessable_entity
    assert_equal Ability::Approval::APPROVE_WITH_TOKEN, response.parsed_body.dig("error", "message")
    assert request.reload.pending?
  end

  test "MCP refuses to approve a token's request, before anyone is asked about the approving" do
    request = approval(source: AbilityGateway::SOURCE_MCP)

    response = Mcp::ToolDispatcher.call(tool: Mcp::Tools::ApproveApproval, server_context: { workspace: @workspace, principal: @admin }, args: { id: request.id })

    assert response.error?
    assert_match Ability::Approval::APPROVE_WITH_TOKEN, Mcp::ToolDispatcher.text_of(response)
    assert request.reload.pending?
    assert_not @workspace.ability_approvals.exists?(action_key: "approvals.update"), "nothing waits on a person for it"
  end

  test "approval rules and unattended rules are never changed with a token, over the API or MCP" do
    post api_v1_approval_rules_url, params: { abilities: [ "catalog.create" ], risk_levels: [ "write" ] }, headers: auth(@admin_token), as: :json
    assert_response :unprocessable_entity
    assert_equal PolicyRule::TOKEN_CHANGE_REFUSAL, response.parsed_body.dig("error", "message")
    assert_empty @workspace.approval_rules

    context = { workspace: @workspace, principal: @admin }
    upsert = Mcp::ToolDispatcher.call(tool: Mcp::Tools::UpsertApprovalRule, server_context: context, args: { abilities: [ "catalog.create" ] })
    assert upsert.error?
    assert_match PolicyRule::TOKEN_CHANGE_REFUSAL, Mcp::ToolDispatcher.text_of(upsert)

    unattended = Mcp::ToolDispatcher.call(tool: Mcp::Tools::DeleteUnattendedRule, server_context: context, args: { id: SecureRandom.uuid })
    assert unattended.error?
    assert_match Ability::UnattendedRule::TOKEN_CHANGE_REFUSAL, Mcp::ToolDispatcher.text_of(unattended)
  end

  test "Halon changes an approval rule for a person in their chat, once they confirm" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    conversation.chat_record
    turn = Conversation::Turn.new(conversation, asker: @admin)
    tool = Chat::Tools::Firefight.new(turn, Mcp::Tools::UpsertApprovalRule, Ability::Action.system!("permissions.create"))

    assert tool.requires_approval?
    tool.call(abilities: [ "catalog.create" ], risk_levels: [ "write" ])

    assert_equal 1, @workspace.approval_rules.count
  end

  private

  def approval(source:, principal: @admin)
    @workspace.ability_approvals.create!(
      principal_type: principal.class.polymorphic_name, principal_id: principal.id, principal_label: principal.principal_label,
      action_key: "catalog.create", request_digest: Ability::Approval.digest("catalog.create", {}, {}), scope: {}, params: {},
      required_role: WorkspaceMembership.roles[:admin], source: source
    )
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }
end
