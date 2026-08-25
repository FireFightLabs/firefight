require "test_helper"

class RefreshPlatformCredentialsJobTest < ActiveJob::TestCase
  test "refreshes every platform's expiring credentials with the configured buffer" do
    manager = mock("token_manager")
    Slack::TokenManager.expects(:new).returns(manager)
    manager.expects(:refresh_all_expiring).with(buffer: RefreshPlatformCredentialsJob::REFRESH_BUFFER)

    RefreshPlatformCredentialsJob.perform_now
  end
end
