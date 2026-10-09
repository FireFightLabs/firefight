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
    Rails.configuration.x.install_notification_webhook_url = nil
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
    assert_equal "onboarding/welcome", JSON.parse(response.body)["component"]

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

  test "the team is told of a workspace created through Google, naming the method" do
    configure_team_webhook!
    google_sign_in("told@example.com")

    post signup_workspace_path, params: { name: "Told Co" }

    workspace = Workspace.find_by!(name: "Told Co")
    membership = workspace.workspace_memberships.sole
    assert_enqueued_jobs 1, only: SignupNotificationJob
    assert_enqueued_with(job: SignupNotificationJob,
                         args: [ SignupNotificationService::WORKSPACE_CREATED, workspace.id, membership.id, UserIdentity::GOOGLE ])
  end

  test "the team is told of a workspace created through an email link, for someone new and for someone known" do
    configure_team_webhook!
    post consume_email_sign_in_path, params: { token: LoginToken.issue!(email: "linked@example.com") }
    post signup_workspace_path, params: { name: "Linked Co", person_name: "Lin Ked" }

    known = User.create!(email: "known@example.com", name: "Known")
    post consume_email_sign_in_path, params: { token: LoginToken.issue!(email: known.email) }
    post signup_workspace_path, params: { name: "Known Co" }

    [ "Linked Co", "Known Co" ].each do |name|
      workspace = Workspace.find_by!(name: name)
      assert_enqueued_with(job: SignupNotificationJob,
                           args: [ SignupNotificationService::WORKSPACE_CREATED, workspace.id, workspace.workspace_memberships.sole.id, UserIdentity::EMAIL ])
    end
  end

  test "a workspace created through a Slack sign-in is told once, as created with Slack, not again when it connects" do
    configure_team_webhook!
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.stubs(:start!).returns(OpenStruct.new(id: "wf-1", status: "running"))
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_ONCE", info: { email: "once@example.com", team_id: "T_ONCE", team_name: "Once Co" }
    )
    get "/auth/slack_openid/callback"
    post signup_workspace_path, params: { name: "Once Co" }
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      uid: "U_ONCE", extra: { team_info: { "id" => "T_ONCE", "name" => "Once Co" } }
    )
    get "/auth/slack/callback"

    workspace = Workspace.find_by!(name: "Once Co")
    assert workspace.chat_connected?
    assert_enqueued_jobs 1, only: SignupNotificationJob
    assert_enqueued_with(job: SignupNotificationJob,
                         args: [ SignupNotificationService::WORKSPACE_CREATED, workspace.id, workspace.workspace_memberships.sole.id, UserIdentity::SLACK ])
  end

  test "with no team webhook set, signing up by every method enqueues nothing and works as before" do
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.stubs(:start!).returns(OpenStruct.new(id: "wf-1", status: "running"))

    google_sign_in("quiet@example.com")
    post signup_workspace_path, params: { name: "Quiet Co" }
    assert_redirected_to onboarding_welcome_path

    post consume_email_sign_in_path, params: { token: LoginToken.issue!(email: "hush@example.com") }
    post signup_workspace_path, params: { name: "Hush Co", person_name: "Hush" }
    assert_redirected_to onboarding_welcome_path

    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_MUTE", info: { email: "mute@example.com", team_id: "T_MUTE", team_name: "Mute Co" }
    )
    get "/auth/slack_openid/callback"
    post signup_workspace_path, params: { name: "Mute Co" }
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(uid: "U_MUTE", extra: { team_info: { "id" => "T_MUTE", "name" => "Mute Co" } })
    get "/auth/slack/callback"
    assert_redirected_to dashboard_path

    assert Workspace.find_by!(name: "Mute Co").chat_connected?
    assert Workspace.exists?(name: "Quiet Co")
    assert Workspace.exists?(name: "Hush Co")
    assert_no_enqueued_jobs only: SignupNotificationJob
  end

  test "a Slack sign-in from a new team by someone who owns one workspace without Slack carries on in it" do
    configure_team_webhook!
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.expects(:start!).once.returns(OpenStruct.new(id: "wf-1", status: "running"))
    owner = User.create!(email: "returning@example.com", name: "Rae Returning")
    membership = Workspace.sign_up!(name: "Returning Co", user: owner)
    workspace = membership.workspace
    onboarding = workspace.onboarding
    onboarding.update!(ai_choice: WorkspaceOnboarding::AI_ACCOUNT, ai_chosen_at: 1.day.ago, permissions_reviewed_at: 1.day.ago,
                       stack_answers: { "observability" => WorkspaceOnboarding::ANSWER_UNUSED })
    clear_enqueued_jobs

    assert_no_difference -> { Workspace.count } do
      assert_no_difference -> { WorkspaceOnboarding.count } do
        slack_openid_sign_in(owner, uid: "U_RAE", team_id: "T_RETURNING", team_name: "Returning Slack")
      end
    end

    assert_redirected_to onboarding_welcome_path
    assert_equal owner.id, session[:user_id]
    assert_equal workspace.id, session[:workspace_id]
    assert_equal workspace.id, session[:connecting_workspace_id]
    assert_equal "T_RETURNING", session[:pending_team_id]
    assert_nil session[:signup_user_id]

    onboarding.reload
    assert_equal workspace.reload.onboarding, onboarding, "the same onboarding row carries on"
    assert_equal WorkspaceOnboarding::AI_ACCOUNT, onboarding.ai_choice
    assert onboarding.permissions_reviewed_at.present?
    assert_equal({ "observability" => WorkspaceOnboarding::ANSWER_UNUSED }, onboarding.stack_answers)
    assert_equal membership, onboarding.installer

    get onboarding_welcome_path, headers: inertia_headers
    assert_equal "onboarding/welcome", JSON.parse(response.body)["component"]

    post onboarding_connect_slack_path
    assert_equal "T_RETURNING", session[:pending_team_id]

    assert_no_difference -> { Workspace.count } do
      slack_install(uid: "U_RAE", team_id: "T_RETURNING")
    end

    assert_redirected_to dashboard_path
    assert_equal SlackAuthenticationService::CONNECTED_MESSAGE, flash[:notice]
    workspace.reload
    assert workspace.chat_connected?
    assert_equal "T_RETURNING", workspace.platform_id
    assert_equal "Returning Co", workspace.name
    assert_equal onboarding, workspace.onboarding
    assert_enqueued_with(job: SignupNotificationJob,
                         args: [ SignupNotificationService::CHAT_CONNECTED, workspace.id, membership.id, nil ])
  end

  test "a workspace carried on from a Slack sign-in connects only the team that person signed in with" do
    SlackWorkspaceSetupWorkflow.expects(:start!).never
    owner = User.create!(email: "careful@example.com", name: "Cass Careful")
    workspace = Workspace.sign_up!(name: "Careful Co", user: owner).workspace
    slack_openid_sign_in(owner, uid: "U_CASS", team_id: "T_CAREFUL", team_name: "Careful Slack")

    slack_install(uid: "U_CASS", team_id: "T_SOMEONE_ELSE")

    assert_redirected_to dashboard_path
    assert_equal SlackAuthenticationService::WORKSPACE_MISMATCH_MESSAGE, flash[:alert]
    assert_not workspace.reload.chat_connected?
  end

  test "someone who owns several workspaces without Slack chooses one, told apart by when each was made, and only their own are offered" do
    owner = User.create!(email: "many@example.com", name: "Max Many")
    first = Workspace.sign_up!(name: "Many Co", user: owner).workspace
    second = Workspace.sign_up!(name: "Many Co", user: owner).workspace
    first.update_columns(created_at: Time.utc(2026, 10, 8, 10, 4, 52))
    second.update_columns(created_at: Time.utc(2026, 10, 8, 22, 32, 52))
    stranger = User.create!(email: "stranger@example.com", name: "Sam Stranger")
    joined = Workspace.sign_up!(name: "Joined Co", user: stranger).workspace
    joined.workspace_memberships.create!(user: owner, role: :admin, joined_at: Time.current)
    someone_elses = Workspace.sign_up!(name: "Someone Else Co", user: stranger).workspace

    assert_no_difference -> { Workspace.count } do
      slack_openid_sign_in(owner, uid: "U_MAX", team_id: "T_MANY", team_name: "Many Slack")
    end
    assert_redirected_to signup_workspace_path
    assert_nil session[:user_id]

    get signup_workspace_path, headers: inertia_headers
    assert_equal "signup/workspace", JSON.parse(response.body)["component"]
    assert_equal [
      { "id" => first.id, "name" => "Many Co", "createdAt" => "2026-10-08T10:04:52Z" },
      { "id" => second.id, "name" => "Many Co", "createdAt" => "2026-10-08T22:32:52Z" }
    ], inertia_props["unconnectedWorkspaces"]

    assert_no_difference -> { Workspace.count } do
      post signup_workspace_path, params: { name: "Silent Co" }
    end
    assert_redirected_to signup_workspace_path
    assert_nil Workspace.find_by(name: "Silent Co")

    [ joined, someone_elses ].each do |not_offered|
      post reuse_signup_workspace_path, params: { workspace_id: not_offered.id }
      assert_redirected_to signup_workspace_path
      assert_equal WorkspaceSignupsController::UNKNOWN_WORKSPACE_MESSAGE, flash[:alert]
      assert_nil session[:user_id]
    end

    assert_no_difference -> { Workspace.count } do
      post reuse_signup_workspace_path, params: { workspace_id: second.id }
    end
    assert_redirected_to onboarding_welcome_path
    assert_equal owner.id, session[:user_id]
    assert_equal second.id, session[:workspace_id]
    assert_equal second.id, session[:connecting_workspace_id]
    assert_equal "T_MANY", session[:pending_team_id]
  end

  test "someone who owns several workspaces without Slack may say to create a new one" do
    owner = User.create!(email: "fresh-start@example.com", name: "Fay Fresh")
    Workspace.sign_up!(name: "Old One", user: owner)
    Workspace.sign_up!(name: "Old Two", user: owner)
    slack_openid_sign_in(owner, uid: "U_FAY", team_id: "T_FRESH_START", team_name: "Fresh Start")

    assert_difference -> { Workspace.count }, 1 do
      post signup_workspace_path, params: { name: "Fresh Start", create_new: true }
    end

    workspace = Workspace.find_by!(name: "Fresh Start")
    assert_redirected_to onboarding_welcome_path
    assert_equal workspace.id, session[:workspace_id]
    assert_equal workspace.id, session[:connecting_workspace_id]
    assert_equal "T_FRESH_START", session[:pending_team_id]
  end

  test "someone whose workspaces are all connected to other Slack teams creates a new one for this team" do
    alice = users(:alice)
    slack_openid_sign_in(alice, uid: "U_ALICE_ELSEWHERE", team_id: "T_ALICE_NEW", team_name: "Alice New Team")
    assert_redirected_to signup_workspace_path

    get signup_workspace_path, headers: inertia_headers
    assert_equal [], inertia_props["unconnectedWorkspaces"]

    assert_difference -> { Workspace.count }, 1 do
      post signup_workspace_path, params: { name: "Alice New Team" }
    end

    workspace = Workspace.find_by!(name: "Alice New Team")
    assert workspace.workspace_memberships.exists?(user: alice, role: :owner)
    assert_redirected_to onboarding_welcome_path
    assert_equal "T_ALICE_NEW", session[:pending_team_id]
  end

  test "a workspace carried on before its founder letter shows the letter once, then continues to setup" do
    owner = User.create!(email: "unread@example.com", name: "Uma Unread")
    onboarding = Workspace.sign_up!(name: "Unread Co", user: owner).workspace.onboarding
    assert onboarding.founder_letter_pending?

    slack_openid_sign_in(owner, uid: "U_UMA", team_id: "T_UNREAD", team_name: "Unread Slack")
    assert_redirected_to onboarding_welcome_path

    get onboarding_welcome_path, headers: inertia_headers
    assert_equal "onboarding/welcome", JSON.parse(response.body)["component"]
    assert_not onboarding.reload.founder_letter_pending?

    get onboarding_welcome_path
    assert_redirected_to dashboard_path
    get dashboard_path
    assert_redirected_to onboarding_checklist_path
  end

  test "a workspace carried on after its founder letter goes straight back to setup where it was left" do
    owner = User.create!(email: "read@example.com", name: "Rex Read")
    onboarding = Workspace.sign_up!(name: "Read Co", user: owner).workspace.onboarding
    onboarding.update!(founder_letter_seen_at: 2.days.ago, ai_choice: WorkspaceOnboarding::AI_ACCOUNT, ai_chosen_at: 2.days.ago)
    seen_at = onboarding.founder_letter_seen_at

    slack_openid_sign_in(owner, uid: "U_REX", team_id: "T_READ", team_name: "Read Slack")
    get onboarding_welcome_path
    assert_redirected_to dashboard_path
    get dashboard_path
    assert_redirected_to onboarding_checklist_path

    onboarding.reload
    assert_equal seen_at, onboarding.founder_letter_seen_at
    assert_equal WorkspaceOnboarding::AI_ACCOUNT, onboarding.ai_choice
  end

  test "a workspace carried on is not sent to a hosted build's plan picker again, and a new one still is" do
    send_new_workspaces_to!("/app/billing/plans")
    owner = User.create!(email: "subscribed@example.com", name: "Sue Subscribed")
    Workspace.sign_up!(name: "Subscribed Co", user: owner)

    slack_openid_sign_in(owner, uid: "U_SUE", team_id: "T_SUBSCRIBED", team_name: "Subscribed Slack")
    assert_redirected_to onboarding_welcome_path

    other = User.create!(email: "two-plans@example.com", name: "Tia Two")
    Workspace.sign_up!(name: "Plan One", user: other)
    Workspace.sign_up!(name: "Plan Two", user: other)
    slack_openid_sign_in(other, uid: "U_TIA", team_id: "T_TWO_PLANS", team_name: "Two Plans")
    post reuse_signup_workspace_path, params: { workspace_id: Workspace.find_by!(name: "Plan Two").id }
    assert_redirected_to onboarding_welcome_path

    delete logout_path
    slack_openid_sign_in(other, uid: "U_TIA", team_id: "T_THIRD_PLAN", team_name: "Third Plan")
    post signup_workspace_path, params: { name: "Third Plan", create_new: true }
    assert_redirected_to "/app/billing/plans"
  end

  test "a Google sign-in with no workspace is offered nothing to carry on in" do
    google_sign_in("nobody-yet@example.com")

    get signup_workspace_path, headers: inertia_headers
    assert_equal [], inertia_props["unconnectedWorkspaces"]
  end

  private

  def configure_team_webhook!
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
  end

  def slack_openid_sign_in(user, uid:, team_id:, team_name:)
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: uid, info: { email: user.email, name: user.name, team_id: team_id, team_name: team_name }
    )
    get "/auth/slack_openid/callback"
  end

  def slack_install(uid:, team_id:)
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      uid: uid, extra: { team_info: { "id" => team_id, "name" => "Slack Name" } }
    )
    get "/auth/slack/callback"
  end

  def google_sign_in(email, name: "Test User")
    auth = mock_google_auth_hash(info: { email: email, unverified_email: email, email_verified: true, name: name })
    get google_callback_path, env: { "omniauth.auth" => auth }
  end
end
