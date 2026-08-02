require "test_helper"

class Auth::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  fixtures :incident_lifecycle_stages, :workspaces, :users, :workspace_memberships, :invite_codes

  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.mock_auth[:slack]        = nil
    OmniAuth.config.test_mode = false
  end

  # slack_openid — OIDC sign-in

  test "slack_openid signs in an existing member and redirects to dashboard" do
    workspace = workspaces(:slack_workspace_one)
    alice     = users(:alice)
    existing  = workspace_memberships(:alice_workspace_one)

    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: existing.platform_user_id,
      info: { email: alice.email, team_id: workspace.platform_id, team_name: workspace.name }
    )

    get "/auth/slack_openid/callback"

    assert_redirected_to dashboard_path
    assert_equal alice.id,     session[:user_id]
    assert_equal workspace.id, session[:workspace_id]
    assert_nil flash[:notice], "a returning sign-in announces nothing"
  end

  test "slack_openid with no workspace kicks off invite-code flow" do
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      info: { email: "installer@example.com", team_id: "T_NEW", team_name: "Brand New Co" }
    )

    get "/auth/slack_openid/callback"

    assert_redirected_to onboarding_invite_code_path
    user = User.find_by(email: "installer@example.com")
    assert user.present?
    assert_equal user.id, session[:pending_user_id]
    assert_equal "T_NEW", session[:pending_team_id]
    assert_equal "Brand New Co", session[:pending_team_name]
    assert_nil session[:user_id]
    assert_nil session[:workspace_id]
  end

  test "slack_openid auto-provisions a new member for an existing workspace without an invite" do
    workspace = workspaces(:slack_workspace_one)

    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_BRAND_NEW",
      info: { email: "brand.new@example.com", team_id: workspace.platform_id, team_name: workspace.name }
    )

    assert_difference -> { workspace.workspace_memberships.count }, 1 do
      get "/auth/slack_openid/callback"
    end

    assert_redirected_to dashboard_path
    new_membership = workspace.workspace_memberships.find_by(platform_user_id: "U_BRAND_NEW")
    assert_equal new_membership.user_id, session[:user_id]
    assert_equal workspace.id,           session[:workspace_id]
    assert_equal "member",               new_membership.role
  end

  # slack — bot install

  test "slack install uses pending_user from session to create workspace + owner membership after invite is claimed" do
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.stubs(:start!).returns(OpenStruct.new(id: "wf-1", status: "running"))

    installer = users(:charlie)
    team_id   = "T_FRESH_INSTALL"

    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_INSTALLER",
      info: { email: installer.email, team_id: team_id, team_name: "Fresh Install Co" }
    )
    get "/auth/slack_openid/callback"
    assert_redirected_to onboarding_invite_code_path
    assert_equal installer.id, session[:pending_user_id]

    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_redirected_to onboarding_install_path

    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      extra: { team_info: { "id" => team_id, "name" => "Fresh Install Co" } }
    )

    assert_difference -> { Workspace.count }, 1 do
      get "/auth/slack/callback"
    end

    workspace = Workspace.find_by(platform: "slack", platform_id: team_id)
    assert workspace.present?
    owner_membership = workspace.workspace_memberships.find_by(user: installer)
    assert owner_membership.present?
    assert_equal "owner", owner_membership.role
    assert_redirected_to onboarding_welcome_path
    assert_equal installer.id, session[:user_id]
    assert_equal workspace.id, session[:workspace_id]
    assert session[:show_welcome_note]
    assert_nil session[:pending_user_id]
    assert_nil session[:pending_team_id]
    assert_nil session[:pending_team_name]
    assert_nil session[:invite_code_id]

    assert invite_codes(:active_public_beta_code).reload.redeemed?
  end

  test "slack install redirects to login when no invite code is claimed for a new workspace" do
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      extra: { team_info: { "id" => "T_DIRECT_INSTALL", "name" => "Direct Install Co" } }
    )

    get "/auth/slack/callback"

    assert_redirected_to login_path
    assert_equal "Public beta access currently requires an invite code.", flash[:alert]
  end

  test "slack_openid redirects to login when the service raises" do
    workspace = workspaces(:slack_workspace_one)
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      info: { email: "boom@example.com", team_id: workspace.platform_id, team_name: workspace.name }
    )
    SlackAuthenticationService.any_instance.stubs(:handle_openid_signin).raises(StandardError, "kaboom")

    get "/auth/slack_openid/callback"

    assert_redirected_to login_path
    assert_equal "Sign-in failed. Please try again.", flash[:alert]
    assert_nil session[:user_id]
  end

  test "slack_openid resets the session on successful sign-in (fixation regression)" do
    workspace = workspaces(:slack_workspace_one)
    existing  = workspace_memberships(:alice_workspace_one)
    alice     = users(:alice)

    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: existing.platform_user_id,
      info: { email: alice.email, team_id: workspace.platform_id, team_name: workspace.name }
    )

    # Direct contract: reset_session must be called on sign-in to mitigate
    # session fixation. (A cookie-rotation probe doesn't work reliably across
    # inertia_rails versions — 3.21+ skips Set-Cookie when no session writes
    # occur during an unauth render, so there's no pre-state to compare.)
    Auth::OmniauthCallbacksController.any_instance.expects(:reset_session).at_least_once

    get "/auth/slack_openid/callback"

    assert_redirected_to dashboard_path
    assert_equal alice.id, session[:user_id]
  end

  # failure

  test "failure with csrf_detected redirects to login with specific alert" do
    get "/auth/failure?message=csrf_detected"

    assert_redirected_to login_path
    assert_equal "Authentication session expired. Please try again.", flash[:alert]
  end

  test "failure with access_denied redirects with denial alert" do
    get "/auth/failure?message=access_denied"

    assert_redirected_to login_path
    assert_equal "You denied access to your Slack account.", flash[:alert]
  end

  test "failure with invalid_credentials redirects with support alert" do
    get "/auth/failure?message=invalid_credentials"

    assert_redirected_to login_path
    assert_equal "Invalid credentials. Please contact support.", flash[:alert]
  end

  test "failure with unknown message falls back to generic alert" do
    get "/auth/failure?message=something_weird"

    assert_redirected_to login_path
    assert_equal "Authentication failed. Please try again.", flash[:alert]
  end
end
