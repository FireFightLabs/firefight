require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  fixtures :incident_lifecycle_stages, :workspaces, :users, :workspace_memberships

  test "GET /login renders login page when unauthenticated" do
    get login_path, headers: inertia_headers
    assert_response :success
  end

  test "GET /login redirects authenticated users to dashboard" do
    sign_in(workspace_memberships(:alice_workspace_one))

    get login_path
    assert_redirected_to dashboard_path
  end

  test "DELETE /logout clears the session and redirects to root" do
    sign_in(workspace_memberships(:alice_workspace_one))

    delete logout_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert_nil session[:workspace_id]
    assert_equal "Signed out successfully", flash[:notice]
  end

  test "DELETE /logout is idempotent when no session exists" do
    delete logout_path
    assert_redirected_to root_path
  end

  private

  def sign_in(membership)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: membership.platform_user_id,
      info: { email: membership.user.email, team_id: membership.workspace.platform_id, team_name: membership.workspace.name }
    )
    get "/auth/slack_openid/callback"
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.test_mode = false
  end
end
