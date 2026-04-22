require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  fixtures :incident_lifecycle_stages, :workspaces, :users, :workspace_memberships, :invite_codes

  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.test_mode = false
  end

  # invite_code

  test "invite_code redirects to login when pending_team_id is missing" do
    get onboarding_invite_code_path

    assert_redirected_to login_path
  end

  test "invite_code renders when pending_team_id is present in session" do
    seed_pending_install("T_NEW_CO", "New Co")

    get onboarding_invite_code_path, headers: inertia_headers

    assert_response :success
    assert_match "New Co", response.body
    assert_match '"inviteCodeClaimed":false', response.body
  end

  test "invite_code clears an expired claimed code and reports not-claimed" do
    seed_pending_install("T_CLEAR_CO", "Clear Co")
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]

    invite_codes(:active_public_beta_code).update!(expires_at: 1.minute.ago)

    get onboarding_invite_code_path, headers: inertia_headers

    assert_response :success
    assert_match '"inviteCodeClaimed":false', response.body
    assert_nil session[:invite_code_id]
  end

  # install

  test "install redirects to login when pending_team_id is missing" do
    get onboarding_install_path

    assert_redirected_to login_path
  end

  test "install redirects to invite-code page when pending install has no claimed code" do
    seed_pending_install("T_NO_CODE", "No Code Co")

    get onboarding_install_path

    assert_redirected_to onboarding_invite_code_path
  end

  test "install renders when pending_team_id is present and invite is claimed" do
    seed_pending_install("T_INSTALL_CO", "Install Co")
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }

    get onboarding_install_path, headers: inertia_headers

    assert_response :success
    assert_match "Install Co", response.body
  end

  # welcome

  test "welcome redirects to login when user is not signed in" do
    get onboarding_welcome_path

    assert_redirected_to login_path
  end

  private

  def seed_pending_install(team_id, team_name)
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      info: { email: "installer@example.com", team_id: team_id, team_name: team_name }
    )
    get "/auth/slack_openid/callback"
    assert_redirected_to onboarding_invite_code_path
  end

  # Inertia headers skip the HTML layout (which would require the Vite manifest
  # to be built in CI) and return JSON props directly. Version must match or
  # Inertia returns 409 Conflict.
  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }
  end
end
