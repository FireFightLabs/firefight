require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @installer = workspace_memberships(:alice_workspace_one)
  end

  test "the installer sees the first-run dialog until they close it" do
    @workspace.create_onboarding!(installer: @installer)
    sign_in(@installer.user, @workspace)

    get dashboard_path, headers: inertia_headers

    assert_response :success
    assert_equal true, inertia_props.dig("onboarding", "dialogPending")
    assert_equal "slack://channel?team=#{@workspace.platform_id}&id=C_INCIDENTS", inertia_props.dig("onboarding", "incidentsChannelUrl")

    @workspace.onboarding.dismiss_dialog!
    get dashboard_path, headers: inertia_headers
    assert_equal false, inertia_props.dig("onboarding", "dialogPending")
  end

  test "another member never sees the dialog" do
    @workspace.create_onboarding!(installer: @installer)
    sign_in(users(:bob), @workspace)

    get dashboard_path, headers: inertia_headers

    assert_equal false, inertia_props.dig("onboarding", "dialogPending")
  end

  test "a workspace installed before onboarding existed shows nothing" do
    sign_in(@installer.user, @workspace)

    get dashboard_path, headers: inertia_headers

    assert_equal false, inertia_props.dig("onboarding", "dialogPending")
  end

  test "a signed-in user with no workspace left is sent back to sign in" do
    ApplicationController.any_instance.stubs(:current_user).returns(users(:alice))
    ApplicationController.any_instance.stubs(:current_workspace).returns(nil)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)

    get dashboard_path

    assert_redirected_to login_path
    assert_equal "Your workspace is no longer on Firefight. Sign in again to install it.", flash[:alert]
  end
end
