require "test_helper"

# GET and PATCH /api/v1/member_access read and set the Who can do what rows through the same model call as the dashboard.
class Api::V1::MemberAccessApiTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Alice personal")
    _, @member_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @bob, on_behalf_of: @bob, name: "Bob personal")
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    @list = northflank.tools.create!(name: "list_services", read_only: true, enabled: true).ability_action
    northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @read = northflank.permission_packs.find_by!(pack: Ability::Role::PACK_READ)
    @changes = northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)
  end

  test "an admin lists each connection's read and change choice with who reaches it through other access" do
    @read.let_members!(Ability::Role::NOBODY)
    Ability::Grant.grant!(workspace: @workspace, principal: @bob, target: { action: @list })

    get api_v1_member_access_index_url, headers: api_headers(token: @admin_token)

    assert_response :success
    row = json_response["connections"].sole
    assert_equal "Faylee (Northflank)", row["connection"]["name"]
    assert_equal [ Ability::Role::NOBODY, @read.slug ], row["read"].values_at("choice", "permission_set")
    assert_equal [ { "permission_set" => nil, "name" => nil, "people" => [ { "id" => @bob.id, "name" => "Bob Jones" } ] } ], row["read"]["through"]
    assert_equal Ability::Role::NOBODY, row["change"]["choice"]
  end

  test "an admin sets a row by its permission set, and the call is in the activity log" do
    patch api_v1_member_access_url(@changes.slug), params: { choice: Ability::Role::CHOSEN, people: [ @bob.id ] }.to_json,
                                                   headers: api_headers(token: @admin_token)

    assert_response :success
    assert_equal [ { "id" => @bob.id, "name" => "Bob Jones" } ], json_response["change"]["people"]
    assert @changes.grants.exists?(principal: @bob)
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "permissions.update", source: AbilityGateway::SOURCE_API)

    patch api_v1_member_access_url(@changes.slug), params: { choice: Ability::Role::EVERYONE }.to_json, headers: api_headers(token: @admin_token)
    assert_equal Ability::Role::EVERYONE, json_response["change"]["choice"]
  end

  test "a refusal is a validation error with the model's sentence, and an unknown person is not found" do
    patch api_v1_member_access_url(@changes.slug), params: { choice: Ability::Role::CHOSEN, people: [] }.to_json, headers: api_headers(token: @admin_token)
    assert_response :unprocessable_entity
    assert_includes response.body, "Pick at least one person, or choose Nobody."

    patch api_v1_member_access_url(@changes.slug), params: { choice: Ability::Role::CHOSEN, people: [ "nobody@example.com" ] }.to_json,
                                                   headers: api_headers(token: @admin_token)
    assert_response :not_found
    assert_not @changes.grants.exists?
  end

  test "a member's personal token can neither read nor set the rows" do
    get api_v1_member_access_index_url, headers: api_headers(token: @member_token)
    assert_response :forbidden

    patch api_v1_member_access_url(@changes.slug), params: { choice: Ability::Role::EVERYONE }.to_json, headers: api_headers(token: @member_token)
    assert_response :forbidden
    assert_not @changes.reload.every_member?
  end
end
