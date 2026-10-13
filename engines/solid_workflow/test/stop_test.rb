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

  test "a stop that fails says why" do
    problems = SolidWorkflow::Definition.new({ "steps" => [ step("stop", "stop", { "outcome" => "failed" }) ], "edges" => [] }).problems

    assert_includes problems, "stop says why it fails the run."
  end
end
