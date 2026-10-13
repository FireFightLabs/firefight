require_relative "test_helper"

# A host can hold a run back, such as a workspace without workflows switched on. A held run keeps its place: nothing is
# claimed, enqueued, woken or swept, and it carries on once let.
class SolidWorkflow::HeldRunsTest < ActiveSupport::TestCase
  include DefinedWorkflowTestHelper

  setup { setup_defined_workflow }

  test "a held run enqueues nothing and runs nothing until let" do
    TestDefinedWorkflow.held = true
    workflow = nil
    assert_no_enqueued_jobs(only: SolidWorkflow::RunStepJob) do
      workflow = TestDefinedWorkflow.start!(@subject, definition: { "steps" => [ step("only", "echo") ], "edges" => [] })
    end

    SolidWorkflow::RunStepJob.perform_now(workflow.steps.sole.id)
    assert workflow.steps.sole.reload.pending?

    travel 10.minutes do
      assert_no_enqueued_jobs(only: SolidWorkflow::OrchestrateJob) { SolidWorkflow::SweeperJob.perform_now }
    end

    TestDefinedWorkflow.held = false
    travel 10.minutes do
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end
    assert workflow.reload.succeeded?
  end

  test "a held run is not woken at its time, and the sweeper wakes it once let" do
    workflow = run_definition({ "steps" => [ step("pause", "delay", { "minutes" => 5 }) ], "edges" => [] })
    pause = workflow.steps.sole
    TestDefinedWorkflow.held = true

    travel 6.minutes do
      perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(pause.id) }
      assert pause.reload.waiting?
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
      assert pause.reload.waiting?

      TestDefinedWorkflow.held = false
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end
    assert workflow.reload.succeeded?
  end

  test "a signal to a held run is kept and acted on once let" do
    workflow = run_definition({ "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 3600) ], "edges" => [] })
    TestDefinedWorkflow.held = true

    perform_enqueued_jobs { SolidWorkflow.signal!("reply", { "said" => "yes" }) }
    assert workflow.reload.waiting?

    TestDefinedWorkflow.held = false
    travel 10.minutes do
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end
    assert workflow.reload.succeeded?
    assert_equal({ "said" => "yes" }, output_of(workflow, "reply")["event"])
  end

  test "class workflows are never held" do
    assert ExampleCalculationWorkflow.runnable?(nil)
  end
end
