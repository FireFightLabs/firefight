require "test_helper"

class MemoryReminderJobTest < ActiveSupport::TestCase
  test "reminds in each workspace with a chat platform where Halon is available, and a platform failure in one does not stop the rest" do
    workspace = workspaces(:slack_workspace_one)
    Investigation.stubs(:available_for?).returns(false)
    Investigation.stubs(:available_for?).with(workspace).returns(true)
    MemoryPostService.any_instance.expects(:remind!).once.raises(AdapterError::NotConnected)

    assert_nothing_raised { MemoryReminderJob.perform_now }
  end
end
