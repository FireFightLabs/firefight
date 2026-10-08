require "test_helper"

# A deploy stops a worker part way through a step. Solid Queue hands the same job out again, and the step picks up where
# it was without posting twice.
class SolidWorkflow::InterruptedStepTest < ActiveSupport::TestCase
  # The worker stops after the post went out and was checkpointed, before the step is marked done.
  class PostingWorkflow < SolidWorkflow::Base
    workflow_name "test.interrupted_post.v1"
    step :post

    cattr_accessor :posts, default: 0
    cattr_accessor :stop_worker, default: false

    def post(workflow:, step:, input:)
      posted = checkpointed(step) { self.class.posts += 1 }
      raise Interrupt if self.class.stop_worker

      { "posts" => posted }
    end
  end

  setup do
    PostingWorkflow.posts = 0
    PostingWorkflow.stop_worker = true
    @workflow = PostingWorkflow.start!(User.create!(name: "Test User", email: "interrupted-step@example.com"))
    @step = @workflow.steps.find_by!(name: "post")
  end

  test "the same job handed back by a stopped worker takes its step up at once and posts once" do
    job = SolidWorkflow::RunStepJob.new(@step.id)
    assert_raises(Interrupt) { job.perform_now }
    assert @step.reload.running?
    assert_equal job.job_id, @step.claimed_by

    PostingWorkflow.stop_worker = false
    job.perform_now

    assert @step.reload.succeeded?
    assert_equal 1, PostingWorkflow.posts
    assert_equal 2, @step.attempts
    assert @workflow.events.exists?(event_type: SolidWorkflow::Events::Step::RESUMED, step_id: @step.id)
  end

  test "any other job leaves a step another job holds" do
    assert_raises(Interrupt) { SolidWorkflow::RunStepJob.new(@step.id).perform_now }

    PostingWorkflow.stop_worker = false
    SolidWorkflow::RunStepJob.new(@step.id).perform_now

    assert @step.reload.running?
    assert_equal 1, @step.attempts
  end

  test "a step whose job never came back is reset by the sweeper and runs without posting again" do
    assert_raises(Interrupt) { SolidWorkflow::RunStepJob.new(@step.id).perform_now }
    PostingWorkflow.stop_worker = false

    travel SolidWorkflow.orphaned_step_threshold + 1.minute do
      SolidWorkflow::SweeperJob.perform_now
      assert @step.reload.pending?
      SolidWorkflow::RunStepJob.new(@step.id).perform_now
    end

    assert @step.reload.succeeded?
    assert_equal 1, PostingWorkflow.posts
  end
end
