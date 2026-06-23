require "test_helper"

class WorkspaceSwitchesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @user = users(:alice)
    ApplicationController.any_instance.stubs(:current_user).returns(@user)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end

  test "switches to a workspace the user belongs to" do
    target = workspaces(:slack_workspace_two)

    post workspace_switch_path, params: { workspace_id: target.id }

    assert_redirected_to dashboard_path
    assert_equal target.id, session[:workspace_id]
  end

  test "rejects a workspace the user does not belong to" do
    other = workspaces(:slack_workspace_expired)

    post workspace_switch_path, params: { workspace_id: other.id }

    assert_not_equal other.id, session[:workspace_id]
    assert_equal "You don't have access to that workspace", flash[:alert]
  end
end
