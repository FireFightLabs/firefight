require "test_helper"

class Api::V1::GatewayApiTest < ActionDispatch::IntegrationTest
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
    @environment = @workspace.environment_entries.first || create_environment!
  end

  def create_environment!
    type = @workspace.catalog_types.find_by!(system_key: CatalogType::SYSTEM_KEY_ENVIRONMENT)
    type.catalog_entries.create!(workspace: @workspace, name: "Production", slug: "production")
  end

  def post_json(path, body, token: @admin_token)
    post path, params: body.to_json, headers: api_headers(token: token)
  end

  def patch_json(path, body, token: @admin_token)
    patch path, params: body.to_json, headers: api_headers(token: token)
  end

  test "a member's personal token cannot read or change the gateway" do
    get api_v1_abilities_url, headers: api_headers(token: @member_token)
    assert_response :forbidden

    post_json api_v1_permission_sets_url, { name: "Sneaky" }, token: @member_token
    assert_response :forbidden
    assert_equal 0, @workspace.ability_roles.count
  end

  test "abilities and principals list what the permissions screen shows" do
    get api_v1_abilities_url, headers: api_headers(token: @admin_token)
    assert_response :success
    ability = json_response["abilities"].find { |row| row["key"] == "runbooks.update" }
    assert_equal "write", ability["risk_level"]
    assert_equal "Firefight", ability["group"]
    assert_nil json_response["abilities"].find { |row| row["key"] == "permissions.update" }

    get api_v1_principals_url, headers: api_headers(token: @admin_token)
    bob = json_response["principals"].find { |row| row["id"] == @bob.id }
    assert_equal "user", bob["kind"]
    assert_equal "member", bob["implicit_authority"]
  end

  test "permission sets are created with abilities, updated as a whole, and deleted by slug" do
    post_json api_v1_permission_sets_url, { name: "Runbook editors", abilities: [ "runbooks.update", "runbooks.create" ] }
    assert_response :created
    assert_equal "runbook_editors", json_response["slug"]
    assert_equal [ "runbooks.create", "runbooks.update" ], json_response["abilities"]

    patch_json api_v1_permission_set_url("runbook_editors"), { abilities: [ "runbooks.read" ] }
    assert_response :success
    assert_equal [ "runbooks.read" ], json_response["abilities"]

    delete api_v1_permission_set_url("runbook_editors"), headers: api_headers(token: @admin_token)
    assert_response :no_content
    assert_nil @workspace.ability_roles.find_by(slug: "runbook_editors")
  end

  test "grants attach an ability or a set to a principal, scoped by environment slug" do
    post_json api_v1_grants_url, {
      principal_kind: "user", principal_id: @bob.id, ability: "runbooks.update",
      environments: [ @environment.slug ], expires_at: 1.week.from_now.iso8601
    }
    assert_response :created
    grant_id = json_response["id"]
    assert_equal "runbooks.update", json_response["ability"]
    assert_equal [ @environment.slug ], json_response["environments"]
    assert_not_nil json_response["expires_at"]

    post_json api_v1_grants_url, { principal_kind: "user", principal_id: @bob.id, ability: "runbooks.update" }
    assert_response :success
    assert_equal grant_id, json_response["id"]
    assert_equal [], json_response["environments"]

    patch_json api_v1_grant_url(grant_id), { environments: [ @environment.slug ] }
    assert_equal [ @environment.slug ], json_response["environments"]

    get api_v1_grants_url, params: { principal_kind: "user", principal_id: @bob.id }, headers: api_headers(token: @admin_token)
    assert_equal [ grant_id ], json_response["grants"].map { |row| row["id"] }

    delete api_v1_grant_url(grant_id), headers: api_headers(token: @admin_token)
    assert_response :no_content
    assert_equal 0, @bob.ability_grants.count
  end

  test "granting an admin-only ability or an unknown one is refused" do
    post_json api_v1_grants_url, { principal_kind: "user", principal_id: @bob.id, ability: "permissions.update" }
    assert_response :not_found

    post_json api_v1_grants_url, { principal_kind: "robot", principal_id: @bob.id, ability: "runbooks.update" }
    assert_response :not_found
  end

  test "approval rules are managed by id and reordered" do
    post_json api_v1_approval_rules_url, {
      abilities: [ "runbooks.update" ], environments: [ @environment.slug ],
      approvers: [ @bob.id ], notify: "both", self_approval: false
    }
    assert_response :created
    first = json_response
    assert_equal [ "runbooks.update" ], first["abilities"]
    assert_equal [ @environment.slug ], first["environments"]
    assert_equal [ { "kind" => "user", "id" => @bob.id } ], first["approvers"]
    assert_equal "both", first["notify"]
    assert_equal false, first["self_approval"]
    assert_equal "admin", first["approver_role"]

    post_json api_v1_approval_rules_url, { risk_levels: [ "destructive" ] }
    second = json_response
    assert_equal 2, second["priority"]
    assert_equal "channel", second["notify"]

    patch_json api_v1_approval_rule_url(second["id"]), { enabled: false }
    assert_equal false, json_response["enabled"]
    assert_equal [ "destructive" ], json_response["risk_levels"]

    patch_json api_v1_approval_rule_url(first["id"]), { approvers: [] }
    assert_equal [], json_response["approvers"]
    assert_equal [ "runbooks.update" ], json_response["abilities"]

    post move_up_api_v1_approval_rule_url(second["id"]), headers: api_headers(token: @admin_token)
    assert_equal 1, json_response["priority"]

    get api_v1_approval_rules_url, headers: api_headers(token: @admin_token)
    assert_equal [ second["id"], first["id"] ], json_response["approval_rules"].map { |row| row["id"] }

    delete api_v1_approval_rule_url(first["id"]), headers: api_headers(token: @admin_token)
    assert_response :no_content
    assert_equal 1, @workspace.approval_rules.count
  end

  test "an approval rule with an approver from another workspace is rejected" do
    post_json api_v1_approval_rules_url, { approvers: [ workspace_memberships(:alice_workspace_two).id ] }
    assert_response :unprocessable_entity
    assert_match "of this workspace", json_response["error"]["errors"].first["message"]
  end

  test "approvals are decided by a person, or by an agent a rule named" do
    approval = @workspace.ability_approvals.create!(
      principal: @bob, principal_label: @bob.principal_label, action_key: "runbooks.update",
      request_digest: "d", required_role: WorkspaceMembership.roles[:admin]
    )
    _, service_token = create_service_key(workspace: @workspace, created_by: @admin, permissions: { "approvals" => [ "read", "update" ] })

    get api_v1_approvals_url, params: { status: "pending" }, headers: api_headers(token: service_token)
    assert_response :success
    assert_equal [ approval.id ], json_response["approvals"].map { |row| row["id"] }

    post approve_api_v1_approval_url(approval), headers: api_headers(token: service_token)
    assert_response :unprocessable_entity
    assert_equal "approval_not_allowed", json_response["error"]["type"]

    post approve_api_v1_approval_url(approval), headers: api_headers(token: @admin_token)
    assert_response :success
    assert_equal "approved", json_response["status"]
    assert_equal @admin.display_name, json_response["approver"]

    post deny_api_v1_approval_url(approval), headers: api_headers(token: @admin_token)
    assert_response :unprocessable_entity
    assert_equal "approval_not_allowed", json_response["error"]["type"]
  end

  test "activity lists the ledger newest first with a decision filter" do
    post_json api_v1_permission_sets_url, { name: "Ledgered" }

    get api_v1_activity_url, params: { decision: "allow" }, headers: api_headers(token: @admin_token)
    assert_response :success
    row = json_response["activity"].first
    assert_equal "permissions.create", row["action_key"]
    assert_equal "api", row["source"]
    assert_equal 1, json_response["pagination"]["page"]
  end

  test "a service key named on a rule that lets agents decide can approve" do
    key, service_token = create_service_key(workspace: @workspace, created_by: @admin, name: "Grok", permissions: { "approvals" => [ "read", "update" ] })
    approval = @workspace.ability_approvals.create!(
      principal: @bob, principal_label: @bob.principal_label, action_key: "runbooks.update",
      request_digest: "d", required_role: WorkspaceMembership.roles[:admin],
      approver_ids: [ { "kind" => "api_key", "id" => key.id } ], agents_may_approve: true
    )

    post approve_api_v1_approval_url(approval), headers: api_headers(token: service_token)
    assert_response :success
    assert_equal "Grok", json_response["approver"]
    assert_equal key, approval.reload.approver
  end
end
