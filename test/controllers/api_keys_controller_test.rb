require "test_helper"

class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships

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
  end

  test "update without permissions key preserves existing permissions" do
    api_key, = ApiKey.create_with_token!(
      workspace:   @workspace,
      created_by:  @workspace.workspace_memberships.first,
      name:        "Existing",
      permissions: { "incidents" => [ "read" ] }
    )

    patch api_key_url(api_key), params: { name: "Renamed" }
    assert_response :redirect
    assert_equal({ "incidents" => [ "read" ] }, api_key.reload.permissions)
  end

  test "update narrows permissions when a smaller set is sent" do
    api_key, = ApiKey.create_with_token!(
      workspace:   @workspace,
      created_by:  @workspace.workspace_memberships.first,
      name:        "Existing",
      permissions: { "incidents" => [ "read", "create" ] }
    )

    patch api_key_url(api_key), params: { name: "Existing", permissions: { "incidents" => [ "read" ] } }
    assert_response :redirect
    assert_equal({ "incidents" => [ "read" ] }, api_key.reload.permissions)
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
