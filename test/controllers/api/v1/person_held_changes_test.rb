require "test_helper"

# A change to who may do what, to keys and agents, to approvals or to webhooks, sent with a token over the REST API,
# waits for an admin to approve it, as it does over MCP. Reads never wait.
class Api::V1::PersonHeldChangesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Alice personal")
  end

  def send_json(verb, path, body = nil, approval_id: nil)
    headers = api_headers(token: @admin_token)
    headers["X-Approval-Id"] = approval_id if approval_id
    public_send(verb, path, params: body&.to_json, headers: headers)
  end

  def assert_held
    assert_response :accepted
    assert_equal "approval_required", json_response.dig("error", "type")
    approval = Ability::Approval.find(json_response["approval_id"])
    assert_equal AbilityGateway::SOURCE_API, approval.source
    approval
  end

  test "an admin's own token waits for a person before granting, and goes through once an admin approves" do
    set = @workspace.ability_roles.create!(name: "Runbook editors", slug: "runbook_editors")
    body = { principal_kind: "user", principal_id: @bob.id, permission_set: set.slug }

    send_json(:post, api_v1_grants_url, body)
    approval = assert_held
    assert_equal 0, @bob.ability_grants.count

    approval.approve!(by: @admin)
    send_json(:post, api_v1_grants_url, body, approval_id: approval.id)

    assert_response :created
    assert_equal 1, @bob.ability_grants.count
  end

  test "member access, keys, agents, approvals and webhooks wait for a person too" do
    agent = @workspace.agents.create!(name: "Deployer", slug: "deployer")
    request = Ability::Approval.create!(
      workspace: @workspace, principal: @bob, principal_label: "Bob", action_key: "catalog.delete",
      request_digest: Ability::Approval.digest("catalog.delete", {}, {}), required_role: WorkspaceMembership.roles[:admin]
    )

    send_json(:patch, api_v1_member_access_url("github_changes"), { choice: "everyone" })
    assert_held
    send_json(:post, api_v1_api_keys_url, { name: "CI" })
    assert_held
    send_json(:post, rotate_api_v1_agent_url(agent.slug))
    assert_held
    send_json(:post, approve_api_v1_approval_url(request))
    assert_held
    send_json(:post, api_v1_webhooks_url, { name: "Hook", url: "https://example.com/hook", subscribed_events: [ "incident.created" ] })
    assert_held

    assert_not @workspace.api_keys.exists?(name: "CI")
    assert_empty agent.live_api_keys
    assert request.reload.pending?
    assert_not @workspace.webhooks.exists?(name: "Hook")
  end

  test "reading them never waits" do
    get api_v1_grants_url, headers: api_headers(token: @admin_token)
    assert_response :success
    get api_v1_webhooks_url, headers: api_headers(token: @admin_token)
    assert_response :success
  end
end
