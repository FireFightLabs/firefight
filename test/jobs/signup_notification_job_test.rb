require "test_helper"

class SignupNotificationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "loads the workspace and member and hands them to the service with the event and method" do
    workspace = workspaces(:slack_workspace_one)
    installer = workspace_memberships(:alice_workspace_one)
    SignupNotificationService.any_instance.expects(:notify)
      .with(SignupNotificationService::WORKSPACE_CREATED, workspace, installer, sign_up_method: UserIdentity::SLACK).once

    SignupNotificationJob.perform_now(SignupNotificationService::WORKSPACE_CREATED, workspace.id, installer.id, UserIdentity::SLACK)
  end

  test "a missing workspace is dropped" do
    SignupNotificationService.any_instance.expects(:notify).never

    assert_nothing_raised do
      SignupNotificationJob.perform_now(SignupNotificationService::WORKSPACE_CREATED, SecureRandom.uuid, SecureRandom.uuid)
    end
  end

  test "a delivery that keeps failing is logged and dropped" do
    workspace = workspaces(:slack_workspace_one)
    installer = workspace_memberships(:alice_workspace_one)
    SignupNotificationService.any_instance.stubs(:notify).raises(SignupNotificationService::DeliveryFailed, "500 Internal Server Error")
    Rails.logger.expects(:warn).with { |payload| payload.is_a?(Hash) && payload[:event] == "signup_notification.failed" }

    assert_nothing_raised do
      perform_enqueued_jobs do
        SignupNotificationJob.perform_later(SignupNotificationService::CHAT_CONNECTED, workspace.id, installer.id)
      end
    end
  end
end
