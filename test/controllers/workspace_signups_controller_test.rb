require "test_helper"

class WorkspaceSignupsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include InviteGateTestHelper

  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    @google_configured = Rails.application.config.x.google_sign_in
    Rails.application.config.x.google_sign_in = true
    OmniAuth.config.test_mode = true
  end

  teardown do
    Rails.application.config.x.google_sign_in = @google_configured
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.mock_auth[:slack] = nil
    OmniAuth.config.test_mode = false
  end

  test "someone new from Google names a workspace, and is made only when they create it" do
    google_sign_in("founder@example.com", name: "Fern Founder")
    assert_redirected_to signup_workspace_path
    assert_nil User.find_by(email: "founder@example.com")

    get signup_workspace_path, headers: inertia_headers

    assert_equal "signup/workspace", JSON.parse(response.body)["component"]
    assert_equal "founder@example.com", inertia_props["email"]
    assert_equal "", inertia_props["suggestedName"]
    assert_equal false, inertia_props["inviteRequired"]

    assert_difference -> { Workspace.count }, 1 do
      post signup_workspace_path, params: { name: "  Fern Labs  " }
    end

    user = User.find_by!(email: "founder@example.com")
    workspace = Workspace.find_by!(created_by: user)
    membership = workspace.workspace_memberships.find_by!(user: user)
    assert_equal "Fern Labs", workspace.name
    assert_not workspace.chat_connected?
    assert_nil workspace.installed_at
    assert membership.owner_role?
    assert_nil membership.platform_user_id
    assert_equal membership, workspace.onboarding.installer
    assert workspace.incident_statuses.any?, "incident configuration is set up"
    assert workspace.incident_severities.any?
    assert workspace.catalog_types.any?, "the catalogue is set up"
    assert UserIdentity.exists?(user: user, provider: UserIdentity::GOOGLE)

    assert_redirected_to onboarding_welcome_path
    assert_equal user.id, session[:user_id]
    assert_equal workspace.id, session[:workspace_id]
    assert_nil session[:signup_claims]

    get onboarding_welcome_path, headers: inertia_headers
    assert_equal "onboarding/welcome", JSON.parse(response.body)["component"]
    assert_equal false, inertia_props["connectSlack"]
  end

  test "a name the workspace refuses leaves nobody behind and says why" do
    google_sign_in("blank@example.com")

    assert_no_difference -> { Workspace.count } do
      post signup_workspace_path, params: { name: "   " }
    end

    assert_redirected_to signup_workspace_path
    assert_nil User.find_by(email: "blank@example.com")

    post signup_workspace_path, params: { name: "x" * (Workspace::NAME_MAX_LENGTH + 1) }
    assert_redirected_to signup_workspace_path
    assert_nil User.find_by(email: "blank@example.com")
  end

  test "an existing person with no workspace signs up as themselves" do
    loner = User.create!(email: "loner@example.com", name: "Loner")
    token = LoginToken.issue!(email: loner.email)
    post consume_email_sign_in_path, params: { token: token }
    assert_redirected_to signup_workspace_path

    get signup_workspace_path, headers: inertia_headers
    assert_equal false, inertia_props["askName"], "someone Firefight knows already has a name"

    post signup_workspace_path, params: { name: "Loner Inc" }

    assert Workspace.find_by!(name: "Loner Inc").workspace_memberships.exists?(user: loner, role: :owner)
    assert_equal loner.id, session[:user_id]
  end

  test "someone new by email gives their name, which an email link cannot carry" do
    post consume_email_sign_in_path, params: { token: LoginToken.issue!(email: "fresh@example.com") }
    get signup_workspace_path, headers: inertia_headers
    assert_equal true, inertia_props["askName"]

    post signup_workspace_path, params: { name: "Fresh Co" }
    assert_redirected_to signup_workspace_path
    assert_nil User.find_by(email: "fresh@example.com")

    post signup_workspace_path, params: { name: "Fresh Co", person_name: " Fran Fresh " }
    assert_equal "Fran Fresh", User.find_by!(email: "fresh@example.com").name
  end

  test "the page waits for self-serve signup and for a sign-in" do
    get signup_workspace_path
    assert_redirected_to login_path

    FeatureFlags.disable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    post signup_workspace_path, params: { name: "Sneaky" }
    assert_redirected_to login_path
    assert_nil Workspace.find_by(name: "Sneaky")
  end

  test "the invite gate asks for a code from every sign-in method" do
    require_invite!
    google_sign_in("gated@example.com")

    get signup_workspace_path, headers: inertia_headers
    assert_equal true, inertia_props["inviteRequired"]

    post signup_workspace_path, params: { name: "Gated Co" }
    assert_redirected_to signup_workspace_path
    assert_nil Workspace.find_by(name: "Gated Co")

    post signup_workspace_path, params: { name: "Gated Co", invite_code: "WRONG" }
    assert_nil Workspace.find_by(name: "Gated Co")

    post signup_workspace_path, params: { name: "Gated Co", invite_code: "beta-access" }

    workspace = Workspace.find_by!(name: "Gated Co")
    code = invite_codes(:active_public_beta_code).reload
    assert code.redeemed?
    assert_equal workspace.created_by, code.redeemed_by
  end

  test "a Slack sign-in from a team Firefight does not know names the workspace after the team, then connects it" do
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.expects(:start!).once.returns(OpenStruct.new(id: "wf-1", status: "running"))
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_SLACK_FOUNDER", info: { email: "slacker@example.com", team_id: "T_SLACK_SIGNUP", team_name: "Slack Team Co" }
    )

    get "/auth/slack_openid/callback"
    assert_redirected_to signup_workspace_path

    get signup_workspace_path, headers: inertia_headers
    assert_equal "Slack Team Co", inertia_props["suggestedName"]

    post signup_workspace_path, params: { name: "Slack Team Co" }
    workspace = Workspace.find_by!(name: "Slack Team Co")
    assert_not workspace.chat_connected?

    get onboarding_welcome_path, headers: inertia_headers
    assert_equal true, inertia_props["connectSlack"]

    get onboarding_install_path, headers: inertia_headers
    assert_equal "onboarding/install", JSON.parse(response.body)["component"]

    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      uid: "U_SLACK_FOUNDER", extra: { team_info: { "id" => "T_SLACK_SIGNUP", "name" => "Slack Team Co" } }
    )
    get "/auth/slack/callback"

    assert_redirected_to dashboard_path
    workspace.reload
    assert workspace.chat_connected?
    assert_equal "T_SLACK_SIGNUP", workspace.platform_id
    assert_equal "U_SLACK_FOUNDER", workspace.workspace_memberships.find_by!(user: workspace.created_by).platform_user_id
  end

  test "a workspace named from a Slack sign-in connects only the team that person signed in with" do
    SlackWorkspaceSetupWorkflow.expects(:start!).never
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_PICKY", info: { email: "picky@example.com", team_id: "T_SIGNED_IN", team_name: "Signed In Co" }
    )
    get "/auth/slack_openid/callback"
    post signup_workspace_path, params: { name: "Signed In Co" }
    workspace = Workspace.find_by!(name: "Signed In Co")

    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      uid: "U_PICKY", extra: { team_info: { "id" => "T_SOMEONE_ELSE", "name" => "Other" } }
    )
    get "/auth/slack/callback"

    assert_redirected_to dashboard_path
    assert_equal SlackAuthenticationService::WORKSPACE_MISMATCH_MESSAGE, flash[:alert]
    assert_not workspace.reload.chat_connected?
  end

  test "a Slack sign-in keeps today's install flow while self-serve signup is off" do
    FeatureFlags.disable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      info: { email: "classic@example.com", team_id: "T_CLASSIC", team_name: "Classic Co" }
    )

    get "/auth/slack_openid/callback"

    assert_redirected_to onboarding_install_path
  end

  test "a hosted build can send a new workspace to its next step, such as choosing a plan" do
    send_new_workspaces_to!("/app/billing/plans")
    google_sign_in("planner@example.com")

    post signup_workspace_path, params: { name: "Planner Co" }

    assert_redirected_to "/app/billing/plans"
  end

  private

  def google_sign_in(email, name: "Test User")
    auth = mock_google_auth_hash(info: { email: email, unverified_email: email, email_verified: true, name: name })
    get google_callback_path, env: { "omniauth.auth" => auth }
  end
end
