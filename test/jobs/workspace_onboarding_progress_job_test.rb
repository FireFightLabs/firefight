require "test_helper"

class WorkspaceOnboardingProgressJobTest < ActiveSupport::TestCase
  test "redraws the welcome message and lets the coach post the next step" do
    workspace = workspaces(:slack_workspace_one)
    first = incidents(:active_critical_ws1)
    first.update!(is_test: true)
    onboarding = workspace.create_onboarding!(installer: workspace_memberships(:alice_workspace_one))
    WorkspaceSetupService.any_instance.expects(:refresh_welcome_message).with(workspace).once
    OnboardingWalkthroughService.any_instance.expects(:advance!).with(first).once

    WorkspaceOnboardingProgressJob.perform_now(onboarding.id)
  end

  test "a deleted onboarding is dropped" do
    WorkspaceSetupService.any_instance.expects(:refresh_welcome_message).never

    assert_nothing_raised { WorkspaceOnboardingProgressJob.perform_now(SecureRandom.uuid) }
  end
end
