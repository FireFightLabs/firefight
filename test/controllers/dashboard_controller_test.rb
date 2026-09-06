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
end
