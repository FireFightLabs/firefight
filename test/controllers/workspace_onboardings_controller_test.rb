require "test_helper"

class WorkspaceOnboardingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @installer = workspace_memberships(:alice_workspace_one)
    @onboarding = @workspace.create_onboarding!(installer: @installer)
  end

  test "the installer closes the dialog for good" do
    sign_in(@installer.user, @workspace)

    patch dismiss_onboarding_dialog_path

    assert_redirected_to dashboard_path
    assert @onboarding.reload.dialog_dismissed_at.present?
  end

  test "anyone else leaves it untouched" do
    sign_in(users(:bob), @workspace)

    patch dismiss_onboarding_dialog_path

    assert_redirected_to dashboard_path
    assert_nil @onboarding.reload.dialog_dismissed_at
  end
end
