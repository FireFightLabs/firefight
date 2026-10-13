require_relative "test_helper"

class SolidWorkflow::StopTest < ActiveSupport::TestCase
  include DefinedWorkflowTestHelper

  setup { setup_defined_workflow }

  test "a stop that succeeds ends the run, leaving every step that has not run, a waiting one too" do
    definition = {
      "steps" => [
        step("first", "echo"), step("stop", "stop", { "outcome" => "succeeded", "reason" => "Nothing to do" }), step("after", "echo"),
        step("waits", "delay", { "minutes" => 30 })
      ],
      "edges" => [ edge("first", "stop"), edge("stop", "after") ]
    }

    workflow = run_definition(definition)

    assert workflow.succeeded?
    assert_equal({ "outcome" => "succeeded", "reason" => "Nothing to do" }, output_of(workflow, "stop"))
    assert_equal "bypassed", workflow.steps.find_by!(name: "after").status
    assert_equal "bypassed", workflow.steps.find_by!(name: "waits").status
  end

  test "a stop that fails fails the run with its reason, without trying again" do
    definition = { "steps" => [ step("stop", "stop", { "outcome" => "failed", "reason" => "No deploy today" }, retry: { "max_attempts" => 3 }) ], "edges" => [] }

    workflow = run_definition(definition)

    assert workflow.failed?
    stop = workflow.steps.find_by!(name: "stop")
    assert_equal 1, stop.attempts
    assert_match "No deploy today", stop.last_error
  end

  test "a stop whose outcome fills to something it does not know fails the run rather than ending it as succeeded" do
    definition = { "steps" => [ step("stop", "stop", { "outcome" => "{{inputs.outcome}}", "reason" => "Not today" }), step("after", "echo") ],
                   "edges" => [ edge("stop", "after") ] }

    workflow = run_definition(definition, context: { "inputs" => { "outcome" => "Failed" } })

    assert workflow.failed?
    assert_match "succeeded or failed", workflow.steps.find_by!(name: "stop").last_error
  end

  test "a stop cancels what every step it leaves started, a for each between its items too" do
    definition = {
      "steps" => [ step("each", "for_each", { "items" => %w[web api], "concurrency" => 2,
                                              "steps" => [ step("hold", "wait_for_event", { "event" => "go", "key" => "{{item}}" }, timeout_seconds: 600) ],
                                              "edges" => [] }), step("stop", "echo") ],
      "edges" => []
    }
    workflow = run_definition(definition)
    each_step = workflow.steps.find_by!(name: "each")
    each_step.update_columns(status: SolidWorkflow::Step.statuses.fetch("pending"))

    workflow.stop_others!(workflow.steps.find_by!(name: "stop"))

    assert_equal "bypassed", each_step.reload.status
    assert(each_step.children.reload.all?(&:cancelled?))
  end

  test "a stop always ends the run, so it takes no failure setting that would carry on past it" do
    definition = { "steps" => [ step("stop", "stop", { "outcome" => "failed", "reason" => "No" }, on_failure: "continue") ], "edges" => [] }

    assert_includes SolidWorkflow::Definition.new(definition).problems, "stop ends the run when it fails, so it cannot carry on or take an error route."
  end

  test "a stop that fails says why" do
    problems = SolidWorkflow::Definition.new({ "steps" => [ step("stop", "stop", { "outcome" => "failed" }) ], "edges" => [] }).problems

    assert_includes problems, "stop says why it fails the run."
  end
end
