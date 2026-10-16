require "test_helper"

class McpGatewayToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Alice personal"
    )
    _, @member_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @bob, on_behalf_of: @bob, name: "Bob personal"
    )
  end

  # A change to who may do what waits over MCP for a person, so it is approved here as an admin would and made again.
  def call_tool(name, arguments = {}, token: @admin_token)
    result = rpc_call(name, arguments, token)
    held = result["content"].first["text"].to_s.match(PersonApprovalHelper::HELD)
    if held
      Ability::Approval.find(held[:id]).update!(status: Ability::Approval::STATUS_APPROVED, resolved_at: Time.current)
      result = rpc_call(name, arguments.merge(approval_id: held[:id]), token)
    end
    [ result["structuredContent"] || {}, result["isError"], result["content"].first["text"] ]
  end

  def rpc_call(name, arguments, token)
    post mcp_path,
      params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body).fetch("result")
  end

  # Approval rules change only for a person, so the tools are run here as Halon's chat runs them for one who confirmed.
  def as_person(name, arguments)
    tool = FirefightTools.all.find { |tool_class| tool_class.name_value == name }
    response = Mcp::ToolDispatcher.run(tool: tool, workspace: @workspace, principal: @workspace.workspace_memberships.find_by!(role: :owner), args: arguments)
    [ response.structured_content.deep_stringify_keys, response.error?, Mcp::ToolDispatcher.text_of(response) ]
  rescue *Mcp::ToolDispatcher::TOOL_ERRORS => e
    [ {}, true, Mcp::ToolDispatcher.text_of(Mcp::ToolDispatcher.tool_error_response(e)) ]
  end

  test "a member cannot reach the gateway tools" do
    _, error, text = call_tool(FirefightTools::LIST_ABILITIES, {}, token: @member_token)

    assert error
    assert_includes text, "permissions:read"
  end

  test "abilities and principals are listed for an admin" do
    payload, error, = call_tool(FirefightTools::LIST_ABILITIES, { query: "runbooks" })
    assert_not error
    assert_includes payload["abilities"].map { |row| row["key"] }, "runbooks.update"

    payload, = call_tool(FirefightTools::LIST_PRINCIPALS, { kind: "user" })
    assert_includes payload["principals"].map { |row| row["id"] }, @bob.id
  end

  test "permission sets and grants round-trip" do
    payload, error, = call_tool(FirefightTools::UPSERT_PERMISSION_SET, { name: "Runbook editors", abilities: [ "runbooks.update" ] })
    assert_not error
    assert_equal "runbook_editors", payload["slug"]

    payload, = call_tool(FirefightTools::UPSERT_PERMISSION_SET, { slug: "runbook_editors", abilities: [ "runbooks.read", "runbooks.update" ] })
    assert_equal [ "runbooks.read", "runbooks.update" ], payload["abilities"]

    payload, error, = call_tool(FirefightTools::GRANT_ABILITY, {
      principal_kind: "user", principal_id: @bob.id, permission_set: "runbook_editors"
    })
    assert_not error
    assert_equal "runbook_editors", payload["permission_set"]
    grant_id = payload["id"]

    payload, = call_tool(FirefightTools::LIST_PRINCIPALS, { kind: "user" })
    bob = payload["principals"].find { |row| row["id"] == @bob.id }
    assert_equal [ grant_id ], bob["grants"].map { |grant| grant["id"] }

    payload, = call_tool(FirefightTools::REVOKE_GRANT, { grant_id: grant_id })
    assert payload["revoked"]
    assert_equal 0, @bob.ability_grants.count

    payload, = call_tool(FirefightTools::DELETE_PERMISSION_SET, { slug: "runbook_editors" })
    assert payload["deleted"]
    assert_nil @workspace.ability_roles.find_by(slug: "runbook_editors")
  end

  test "approval rules are created, changed in part, and deleted for a person, and never with a token" do
    payload, error, text = as_person(FirefightTools::UPSERT_APPROVAL_RULE, {
      risk_levels: [ "destructive" ], approvers: [ { kind: "user", id: @bob.id } ], notify: "dm", self_approval: false
    })
    assert_not error, text
    assert_equal [ { "kind" => "user", "id" => @bob.id } ], payload["approvers"]
    assert_equal "dm", payload["notify"]
    id = payload["id"]

    payload, = as_person(FirefightTools::UPSERT_APPROVAL_RULE, { id: id, enabled: false })
    assert_equal false, payload["enabled"]
    assert_equal [ "destructive" ], payload["risk_levels"]
    assert_equal [ { "kind" => "user", "id" => @bob.id } ], payload["approvers"]

    _, error, text = as_person(FirefightTools::UPSERT_APPROVAL_RULE, { id: SecureRandom.uuid, enabled: true })
    assert error
    assert_includes text, "Not found"

    _, error, text = call_tool(FirefightTools::DELETE_APPROVAL_RULE, { id: id })
    assert error, "never with a token"
    assert_includes text, PolicyRule::TOKEN_CHANGE_REFUSAL

    payload, = as_person(FirefightTools::DELETE_APPROVAL_RULE, { id: id })
    assert payload["deleted"]
    assert_equal 0, @workspace.approval_rules.count
  end

  test "activity shows what the gateway tools did" do
    call_tool(FirefightTools::UPSERT_PERMISSION_SET, { name: "Ledgered" })

    payload, error, = call_tool(FirefightTools::SEARCH_ACTIVITY, { decision: "allow", ability: "permissions.create" })
    assert_not error
    row = payload["activity"].first
    assert_equal "mcp", row["source"]
    assert_equal "permissions.create", row["ability"]
  end

  test "the gateway tools are advertised" do
    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@admin_token}" }
    names = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }

    [ FirefightTools::LIST_ABILITIES, FirefightTools::GRANT_ABILITY, FirefightTools::UPSERT_APPROVAL_RULE, FirefightTools::SEARCH_ACTIVITY ].each do |name|
      assert_includes names, name
    end
  end
end
