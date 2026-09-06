require "test_helper"

class InstallNotificationJobTest < ActiveSupport::TestCase
  test "loads the workspace and installer and hands them to the service" do
    workspace = workspaces(:slack_workspace_one)
    installer = workspace_memberships(:alice_workspace_one)
    InstallNotificationService.any_instance.expects(:notify).with(workspace, installer).once

    InstallNotificationJob.perform_now(workspace.id, installer.id)
  end

  test "a missing workspace is dropped" do
    InstallNotificationService.any_instance.expects(:notify).never

    assert_nothing_raised { InstallNotificationJob.perform_now(SecureRandom.uuid, SecureRandom.uuid) }
  end
end
