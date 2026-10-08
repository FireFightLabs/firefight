require "test_helper"

class InterruptedJobTest < ActiveSupport::TestCase
  include QueueTablesHelper

  test "a job failed because its worker was killed runs again, and only that kind of failure" do
    with_queue_tables do
      killed = SolidQueue::Job.enqueue(ChannelArchivalJob.new("incident", "at"))
      kill_worker_holding(killed)
      assert killed.failed?

      raised = SolidQueue::Job.enqueue(ChannelArchivalJob.new("other", "at"))
      raised.ready_execution.destroy!
      SolidQueue::FailedExecution.create!(job: raised, exception: RuntimeError.new("the job's own error"))

      assert_equal 1, InterruptedJob.run_again!

      assert killed.reload.ready?
      assert_equal 1, killed.arguments[InterruptedJob::COUNT]
      assert raised.reload.failed?, "a job that raised is left for whoever reads the failures"
    end
  end

  test "a job that keeps stopping its worker is given up on once, and its class is told" do
    with_queue_tables do
      job = SolidQueue::Job.enqueue(PostmortemGenerationJob.new("incident-id"))

      InterruptedJob::GIVE_UP_AFTER.times do
        kill_worker_holding(job)
        assert_equal 1, InterruptedJob.run_again!
      end

      kill_worker_holding(job)
      PostmortemGenerationJob.expects(:interrupted_too_often).with("incident-id").once
      assert_equal 0, InterruptedJob.run_again!
      assert_equal 0, InterruptedJob.run_again!
      assert job.reload.failed?, "it stays failed, so the operator console shows it"
    end
  end

  test "a chat turn is left for its own recovery, which never runs again a turn that may have changed something" do
    with_queue_tables do
      job = SolidQueue::Job.enqueue(ConversationReplyJob.new("conversation-id", "asker-id", nil))
      kill_worker_holding(job)

      assert_equal 0, InterruptedJob.run_again!
      assert job.reload.failed?
    end
  end
end
