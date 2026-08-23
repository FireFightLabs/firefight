require "test_helper"

class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create with well-formed permissions persists key" do
    assert_difference -> { ApiKey.count }, 1 do
      post api_keys_url, params: {
        name: "Datadog",
        permissions: { "incidents" => [ "read", "create" ] }
      }
    end
    assert_response :redirect
  end

  test "create rejects unknown resource" do
    assert_no_difference -> { ApiKey.count } do
      post api_keys_url, params: {
        name: "Bad",
        permissions: { "delete_all_data" => [ "execute" ] }
      }
    end
    assert_response :redirect
    assert_match(/unknown permission/, flash[:alert])
  end

  test "update without permissions key preserves existing permissions" do
    api_key, = create_service_key(
      workspace: @workspace, created_by: @workspace.workspace_memberships.first,
      name: "Existing", permissions: { "incidents" => [ "read" ] }
    )

    patch api_key_url(api_key), params: { name: "Renamed" }
    assert_response :redirect
    assert_equal({ "incidents" => [ "read" ] }, api_key.reload.granted_permissions)
  end

  test "update narrows permissions when a smaller set is sent" do
    api_key, = create_service_key(
      workspace: @workspace, created_by: @workspace.workspace_memberships.first,
      name: "Existing", permissions: { "incidents" => [ "read", "create" ] }
    )

    patch api_key_url(api_key), params: { name: "Existing", permissions: { "incidents" => [ "read" ] } }
    assert_response :redirect
    assert_equal({ "incidents" => [ "read" ] }, api_key.reload.granted_permissions)
  end

  test "a rejected permission set leaves the key untouched" do
    api_key, = create_service_key(
      workspace: @workspace, created_by: @workspace.workspace_memberships.first,
      name: "Existing", permissions: { "incidents" => [ "read" ] }
    )

    patch api_key_url(api_key), params: { name: "Renamed", permissions: { "nonsense" => [ "read" ] } }

    assert_equal({ "incidents" => [ "read" ] }, api_key.reload.granted_permissions)
    assert_equal "Existing", api_key.name, "the rename must roll back with the permissions"
  end

  test "a member can mint a personal token but not a service key" do
    sign_in(users(:bob), @workspace)

    assert_difference -> { ApiKey.count }, 1 do
      post api_keys_url, params: { kind: "personal", name: "Bob's Claude Code" }
    end
    key = ApiKey.find_by!(name: "Bob's Claude Code")
    assert key.personal?
    assert_equal workspace_memberships(:bob_workspace_one), key.on_behalf_of

    assert_no_difference -> { ApiKey.count } do
      post api_keys_url, params: { name: "Sneaky service key", permissions: { incidents: [ "read" ] } }
    end
    assert_redirected_to dashboard_path
  end

  test "abilities preview shows resolved grants for service keys and implicit reads for personal" do
    service_key = create_service_key(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), name: "Scoped",
      permissions: { ApiKey::RESOURCE_ALERTS => [ ApiKey::ACTION_READ ] }
    ).first

    get abilities_api_key_url(service_key)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "service", body["mode"]
    assert_equal [ "alerts.read" ], body["abilities"].map { |a| a["action_key"] }
    assert_equal "read", body["abilities"].first["risk_level"]

    personal_key = create_service_key(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one),
      on_behalf_of: workspace_memberships(:alice_workspace_one), name: "Personal"
    ).first

    get abilities_api_key_url(personal_key)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "personal", body["mode"]
    assert body["abilities"].all? { |a| a["implicit"] && a["risk_level"] == "read" }
  end

  test "a member cannot touch another principal's key" do
    admin_key = create_service_key(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), name: "Admin key"
    ).first
    sign_in(users(:bob), @workspace)

    delete api_key_url(admin_key)

    assert_response :not_found
    assert_nil admin_key.reload.deleted_at
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
