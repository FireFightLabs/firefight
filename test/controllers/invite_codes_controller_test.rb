require "test_helper"

class InviteCodesControllerTest < ActionDispatch::IntegrationTest
  fixtures :incident_lifecycle_stages, :workspaces, :users, :workspace_memberships, :invite_codes

  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.test_mode = false
  end

  test "create stores invite code in session and redirects to install when code is valid" do
    seed_pending_install_session

    post claim_invite_code_path, params: { code: "BETA-ACCESS" }

    assert_redirected_to onboarding_install_path
    assert_equal "Invite code accepted. You can install Firefight now.", flash[:notice]
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]
  end

  test "create clears session and redirects back to invite-code page when code is invalid" do
    seed_pending_install_session
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]

    post claim_invite_code_path, params: { code: "NOT-A-CODE" }

    assert_redirected_to onboarding_invite_code_path
    assert_equal "That invite code is invalid or expired.", flash[:alert]
    assert_nil session[:invite_code_id]
  end

  test "create redirects to login when there is no pending install in session" do
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }

    assert_redirected_to login_path
    assert_nil session[:invite_code_id]
  end

  test "create replaces the session invite code when a different valid code is claimed" do
    seed_pending_install_session

    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]

    post claim_invite_code_path, params: { code: "EARLY-ACCESS" }

    assert_redirected_to onboarding_install_path
    assert_equal invite_codes(:second_active_public_beta_code).id, session[:invite_code_id]
  end

  private

  def seed_pending_install_session
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      info: { email: "installer@example.com", team_id: "T_SEED", team_name: "Seed Co" }
    )
    get "/auth/slack_openid/callback"
    assert_redirected_to onboarding_invite_code_path
  end
end
