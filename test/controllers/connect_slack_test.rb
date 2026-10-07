require "test_helper"

# Connecting Slack to a workspace that started without it, from the banner every page shows.
class ConnectSlackTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    OmniAuth.config.test_mode = true
    stub_successful_slack_workflow
    @owner = User.create!(email: "owner@example.com", name: "Olive Owner")
    @membership = Workspace.sign_up!(name: "Olive Co", user: @owner)
    @workspace = @membership.workspace
    sign_in_by_email(@owner)
  end

  teardown do
    OmniAuth.config.mock_auth[:slack] = nil
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.test_mode = false
  end

  test "the banner's facts ride on every page, and declaring is refused with the reason" do
    get dashboard_path, headers: inertia_headers

    workspace_props = inertia_props["currentWorkspace"]
    assert_equal false, workspace_props["chatConnected"]
    assert_equal "Connect Slack first to run incidents.", workspace_props["incidentsBlockedReason"]
    assert_equal false, inertia_props.dig("onboarding", "dialogPending")
    assert_nil inertia_props.dig("onboarding", "incidentsChannelUrl")
    assert_equal true, inertia_props.dig("currentUserCan", "workspace")
  end

  test "the dashboard refuses to declare an incident before Slack is connected" do
    severity = @workspace.incident_severities.first

    assert_no_difference -> { Incident.count } do
      post declare_incident_path, params: { answers: { name: "Checkout failing", severity: severity.slug } },
        headers: { "HTTP_REFERER" => dashboard_url }
    end

    assert_redirected_to dashboard_url
    assert_equal "Connect Slack first to run incidents.", flash[:alert]
  end

  test "an admin connects Slack, which fills this workspace and starts its setup" do
    InstallNotificationService.stubs(:configured?).returns(true)
    SlackWorkspaceSetupWorkflow.expects(:start!).with(@workspace, context: { installer_user_id: "U_OLIVE" })
      .returns(OpenStruct.new(id: "wf-1", status: "running"))

    post onboarding_connect_slack_path
    assert_redirected_to onboarding_install_path
    assert_equal @workspace.id, session[:connecting_workspace_id]

    get onboarding_install_path, headers: inertia_headers
    assert_equal "Olive Co", inertia_props["teamName"]
    assert_equal dashboard_path, inertia_props["skipPath"]

    assert_no_difference -> { Workspace.count } do
      assert_enqueued_with(job: InstallNotificationJob, args: [ @workspace.id, @membership.id ]) do
        slack_install(team_id: "T_OLIVE", uid: "U_OLIVE")
      end
    end

    assert_redirected_to dashboard_path
    assert_equal SlackAuthenticationService::CONNECTED_MESSAGE, flash[:notice]
    @workspace.reload
    assert @workspace.chat_connected?
    assert_equal "T_OLIVE", @workspace.platform_id
    assert_equal "Olive Co", @workspace.name
    assert_equal "U_OLIVE", @membership.reload.platform_user_id
    assert_equal @owner.id, session[:user_id]
    assert_nil session[:connecting_workspace_id]
  end

  test "a Slack team already on another Firefight workspace is refused, never merged" do
    taken = workspaces(:slack_workspace_one)
    SlackWorkspaceSetupWorkflow.expects(:start!).never
    post onboarding_connect_slack_path

    slack_install(team_id: taken.platform_id, uid: "U_OLIVE")

    assert_redirected_to dashboard_path
    assert_equal "This Slack workspace is already connected to another Firefight workspace. Sign in with Slack to join it, " \
                 "or ask its admin to invite you.", flash[:alert]
    assert_not @workspace.reload.chat_connected?
    assert_nil @membership.reload.platform_user_id
    assert_equal @owner.id, session[:user_id], "the person stays signed in"
  end

  test "a member who is not an admin cannot connect Slack" do
    member = User.create!(email: "member@example.com", name: "Max Member")
    @workspace.workspace_memberships.create!(user: member, role: :member, joined_at: Time.current)
    delete logout_path
    sign_in_by_email(member)

    get dashboard_path, headers: inertia_headers
    assert_equal false, inertia_props.dig("currentUserCan", "workspace")

    post onboarding_connect_slack_path

    assert_redirected_to dashboard_path
    assert_nil session[:connecting_workspace_id]
  end

  test "a workspace already connected is not connected again" do
    @workspace.connect_slack!(mock_slack_auth_hash(extra: { team_info: { "id" => "T_ALREADY", "name" => "x" } }))

    post onboarding_connect_slack_path

    assert_redirected_to dashboard_path
    assert_equal OnboardingController::ALREADY_CONNECTED_MESSAGE, flash[:alert]
  end

  test "once connected, a teammate who joined by email signs in with Slack and keeps their seat" do
    SlackWorkspaceSetupWorkflow.stubs(:start!).returns(OpenStruct.new(id: "wf-1", status: "running"))
    teammate = User.create!(email: "teammate@example.com", name: "Tess Teammate")
    seat = @workspace.workspace_memberships.create!(user: teammate, role: :member, joined_at: Time.current)
    post onboarding_connect_slack_path
    slack_install(team_id: "T_OLIVE_TEAM", uid: "U_OLIVE")
    delete logout_path

    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: "U_TESS", info: { email: teammate.email, team_id: "T_OLIVE_TEAM", team_name: "Olive Slack" }
    )
    assert_no_difference -> { @workspace.workspace_memberships.count } do
      get "/auth/slack_openid/callback"
    end

    assert_redirected_to dashboard_path
    assert_equal "U_TESS", seat.reload.platform_user_id
    assert_equal teammate.id, session[:user_id]
  end

  private

  def sign_in_by_email(user)
    token = LoginToken.issue!(email: user.email)
    post consume_email_sign_in_path, params: { token: token }
    assert_equal user.id, session[:user_id]
  end

  def slack_install(team_id:, uid:)
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      uid: uid, extra: { team_info: { "id" => team_id, "name" => "Slack Name" } }
    )
    get "/auth/slack/callback"
  end
end
