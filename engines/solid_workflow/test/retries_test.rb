require_relative "test_helper"

class SolidWorkflow::RetriesTest < ActiveSupport::TestCase
  include DefinedWorkflowTestHelper

  setup { setup_defined_workflow }

  test "a failed attempt books the run to move again when its backoff ends" do
    TestDefinedWorkflow.held = true
    workflow = TestDefinedWorkflow.start!(@subject, definition: { "steps" => [ step("call", "fail") ], "edges" => [] })
    TestDefinedWorkflow.held = false
    call = workflow.steps.sole
    call.update_columns(status: "running", attempts: 1, claimed_by: "job-1")

    call.mark_failed!(RuntimeError.new("flaky"), claimed_by: "job-1")

    call.reload
    assert call.pending?
    assert_enqueued_with(job: SolidWorkflow::OrchestrateJob, args: [ workflow.id ], at: call.run_at)
  end

  test "a class workflow's retry is booked for its backoff too" do
    workflow = ExampleCalculationWorkflow.start!(@subject, context: { numbers: [ 1, 2 ] })
    step = workflow.steps.first
    step.update!(status: :failed, attempts: 1)

    step.schedule_retry!

    assert_enqueued_with(job: SolidWorkflow::OrchestrateJob, args: [ workflow.id ], at: step.reload.run_at)
  end

  test "being woken never uses up a step's attempts, so a transient error still retries" do
    workflow = run_definition({ "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 3600) ], "edges" => [] })
    reply = workflow.steps.sole

    (reply.max_attempts + 2).times do
      perform_enqueued_jobs { reply.reload.wake!(reason: "test") }
      assert reply.reload.waiting?
    end

    assert_equal 1, reply.attempts
    assert reply.should_retry?(RuntimeError.new("flaky"))
  end
end
