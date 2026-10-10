require "test_helper"

# Reinstalling Slack from Settings, Workspace, so new scopes are granted to the team already connected.
class ReinstallSlackTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @workspace = Workspace.create!(platform: Platforms::SLACK, platform_id: "T#{SecureRandom.hex(8)}", name: "Acme", installed_at: 1.week.ago,
                                   access_token: "xoxb-live", refresh_token: "xoxe-live", incidents_channel_id: "C1", platform_data: { "name" => "Acme Slack" })
    @workspace.workspace_memberships.create!(user: users(:alice), role: :owner, platform_user_id: "U_ALICE", joined_at: 1.week.ago)
    sign_in(users(:alice), @workspace)
  end

  teardown do
    OmniAuth.config.mock_auth[:slack] = nil
    OmniAuth.config.test_mode = false
  end

  test "the screen names the connected team" do
    get settings_workspace_path, headers: inertia_headers

    assert_equal "Acme Slack", inertia_props.dig("settings", "chatTeamName")
  end

  test "an admin reinstalls into the same team, which refreshes this workspace and creates none" do
    @workspace.mark_disconnected!(Workspace::Connection::DISCONNECTED_TOKEN_REVOKED)
    SlackWorkspaceSetupWorkflow.expects(:start!).never

    post reinstall_slack_path, headers: inertia_headers

    assert_response :conflict
    assert_equal install_slack_app_path, response.headers["X-Inertia-Location"]
    assert_equal @workspace.id, session[:reinstalling_workspace_id]
    assert_equal @workspace.platform_id, session[:pending_team_id]

    assert_no_difference -> { Workspace.count } do
      install(team_id: @workspace.platform_id, name: "Renamed In Slack", token: "xoxb-reinstalled")
    end

    assert_redirected_to settings_workspace_path
    assert_equal "Slack was reinstalled.", flash[:notice]
    @workspace.reload
    assert_equal "xoxb-reinstalled", @workspace.access_token
    assert_equal "Acme", @workspace.name
    assert_not @workspace.disconnected?
    assert_nil session[:reinstalling_workspace_id]
    assert_nil session[:pending_team_id]
  end

  test "choosing a different Slack workspace reinstalls nothing and creates nothing" do
    post reinstall_slack_path

    assert_redirected_to install_slack_app_path
    assert_no_changes -> { @workspace.reload.updated_at } do
      assert_no_difference -> { Workspace.count } do
        install(team_id: "T_SOMEONE_ELSE", name: "Someone Else", token: "xoxb-other")
      end
    end

    assert_redirected_to settings_workspace_path
    assert_equal "Slack was not reinstalled, because you chose a different Slack workspace. Choose Acme Slack and try again.", flash[:alert]
    assert_nil session[:reinstalling_workspace_id]
  end

  test "cancelling in Slack comes back to settings and says so" do
    post reinstall_slack_path

    get "/auth/failure?message=access_denied&strategy=slack"

    assert_redirected_to settings_workspace_path
    assert_equal "You denied access to your Slack account.", flash[:alert]
    assert_nil session[:reinstalling_workspace_id]
  end

  test "a member who is not an admin cannot start a reinstall" do
    @workspace.workspace_memberships.create!(user: users(:bob), role: :member, platform_user_id: "U_BOB", joined_at: 1.week.ago)
    sign_in(users(:bob), @workspace)

    post reinstall_slack_path, headers: { "HTTP_REFERER" => settings_workspace_url }

    assert_redirected_to settings_workspace_url
    assert_match "You don't have permission", flash[:alert]
    assert_nil session[:reinstalling_workspace_id]
  end

  test "a workspace without Slack is told to connect it first" do
    membership = Workspace.sign_up!(name: "Olive Co", user: users(:alice))
    sign_in(users(:alice), membership.workspace)

    post reinstall_slack_path

    assert_redirected_to settings_workspace_path
    assert_equal WorkspaceSettingsController::NOT_CONNECTED_MESSAGE, flash[:alert]
    assert_nil session[:reinstalling_workspace_id]
  end

  test "an install for another team after an abandoned reinstall is never taken for one" do
    post reinstall_slack_path
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(uid: "U_ALICE_NEW", info: { email: users(:alice).email, team_id: "T_NEW_TEAM", team_name: "New Team" })
    get "/auth/slack_openid/callback"
    assert_redirected_to onboarding_install_path
    SlackWorkspaceSetupWorkflow.stubs(:start!).returns(OpenStruct.new(id: "wf-1", status: "running"))

    assert_no_changes -> { @workspace.reload.updated_at } do
      assert_difference -> { Workspace.count }, 1 do
        install(team_id: "T_NEW_TEAM", name: "New Team", token: "xoxb-new-team")
      end
    end

    assert Workspace.exists?(platform: Platforms::SLACK, platform_id: "T_NEW_TEAM")
  ensure
    OmniAuth.config.mock_auth[:slack_openid] = nil
  end

  private

  def install(team_id:, name:, token:)
    OmniAuth.config.mock_auth[:slack] = mock_slack_auth_hash(
      credentials: { token: token, refresh_token: nil, expires_at: nil, expires: false },
      extra: { team_info: { "id" => team_id, "name" => name } }
    )
    get "/auth/slack/callback"
  end
end
