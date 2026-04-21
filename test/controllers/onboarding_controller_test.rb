require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  fixtures :incident_lifecycle_stages, :workspaces, :users, :workspace_memberships

  # install

  test "install redirects to login when pending_team_id is missing" do
    get onboarding_install_path

    assert_redirected_to login_path
  end

  test "install renders when pending_team_id is present in session" do
    # Seed session via OIDC callback — the cleanest way to set pending_* keys
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      info: { email: "installer@example.com", team_id: "T_NEW_FOR_INSTALL", team_name: "Install Co" }
    )
    get "/auth/slack_openid/callback"
    assert_redirected_to onboarding_install_path

    # Inertia headers skip the HTML layout (which would require the Vite
    # manifest to be built in CI) and return JSON props directly. Version must
    # match or Inertia returns 409 Conflict.
    get onboarding_install_path, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }

    assert_response :success
    assert_match "Install Co", response.body
  ensure
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.test_mode = false
  end

  # welcome

  test "welcome redirects to login when user is not signed in" do
    get onboarding_welcome_path

    assert_redirected_to login_path
  end
end
