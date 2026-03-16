require "test_helper"

class RefreshSlackTokensJobTest < ActiveJob::TestCase
  test "refreshes all expiring tokens using configured buffer" do
    manager = mock("token_manager")
    Slack::TokenManager.expects(:new).returns(manager)
    manager.expects(:refresh_all_expiring).with(buffer: RefreshSlackTokensJob::REFRESH_BUFFER)

    RefreshSlackTokensJob.perform_now
  end
end
