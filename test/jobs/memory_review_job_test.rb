require "test_helper"

class MemoryReviewJobTest < ActiveJob::TestCase
  setup do
    Investigation.stubs(:start_refusal).returns(nil)
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).returns([])
    @workspace = workspaces(:slack_workspace_one)
    @other = workspaces(:slack_workspace_two)
    Chat::Memory.create!(workspace: @workspace, text: "web deploys from main", state: Chat::Memory::STATE_UNCONFIRMED)
    Chat::Memory.create!(workspace: @other, text: "Backups run nightly", state: Chat::Memory::STATE_UNCONFIRMED)
  end

  test "every workspace that has the check on gets one review a night, and one that turned it off gets none" do
    @other.update!(memory_review_enabled: false)

    MemoryReviewJob.perform_now
    MemoryReviewJob.perform_now

    assert_equal 1, Chat::MemoryReview.where(workspace: @workspace).count
    assert_not Chat::MemoryReview.exists?(workspace: @other)
  end

  test "one workspace failing never stops the next" do
    MemoryReviewService.any_instance.stubs(:start!).raises(StandardError, "boom")
    Rails.logger.expects(:error).at_least_once

    assert_nothing_raised { MemoryReviewJob.perform_now }
  end
end
