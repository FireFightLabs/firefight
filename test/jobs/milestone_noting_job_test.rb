require "test_helper"

class MilestoneNotingJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "runs the pass for the incident's workspace" do
    MilestoneNotingService.any_instance.expects(:note!).with(@incident).returns([])

    MilestoneNotingJob.perform_now(@incident.id)
  end

  test "a transient provider error is retried rather than lost" do
    MilestoneNotingService.any_instance.stubs(:note!).raises(FirefightAi::TransientError.new("rate limited"))

    assert_enqueued_with(job: MilestoneNotingJob) do
      MilestoneNotingJob.perform_now(@incident.id)
    end
  end

  test "a terminal provider error is discarded rather than burning tokens" do
    MilestoneNotingService.any_instance.stubs(:note!).raises(FirefightAi::TerminalError.new("context too long"))

    assert_no_enqueued_jobs only: MilestoneNotingJob do
      assert_nothing_raised { MilestoneNotingJob.perform_now(@incident.id) }
    end
  end

  test "an incident deleted before the pass ran is discarded" do
    assert_nothing_raised { MilestoneNotingJob.perform_now(SecureRandom.uuid) }
  end
end
