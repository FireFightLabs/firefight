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
  end

  test "invite_code clears an expired claimed code" do
    seed_pending_install("T_CLEAR_CO", "Clear Co")
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]

    invite_codes(:active_public_beta_code).update!(expires_at: 1.minute.ago)

    get onboarding_invite_code_path, headers: inertia_headers

    assert_response :success
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

  test "welcome redirects signed-in users to dashboard when show_welcome_note is not set" do
    membership = workspace_memberships(:alice_workspace_one)
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: membership.platform_user_id,
      info: { email: membership.user.email, team_id: membership.workspace.platform_id, team_name: membership.workspace.name }
    )
    get "/auth/slack_openid/callback"
    assert_redirected_to dashboard_path
    # show_welcome_note is only set on first install, not on regular sign-in.

    get onboarding_welcome_path
    assert_redirected_to dashboard_path
  end

  test "welcome consumes show_welcome_note so it renders exactly once" do
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.stubs(:start!).returns(OpenStruct.new(id: "wf-1", status: "running"))

    # First install path sets show_welcome_note and redirects to /onboarding/welcome.
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_FRESH", info: { email: users(:charlie).email, team_id: "T_WELCOME_TEST", team_name: "Welcome Co" }
    )
    get "/auth/slack_openid/callback"
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      extra: { team_info: { "id" => "T_WELCOME_TEST", "name" => "Welcome Co" } }
    )
    get "/auth/slack/callback"
    assert_redirected_to onboarding_welcome_path

    get onboarding_welcome_path
    assert_response :success

    # Second visit redirects — the flag was consumed.
    get onboarding_welcome_path
    assert_redirected_to dashboard_path
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
