require_relative "test_helper"

class SolidWorkflow::InterpreterTest < ActiveSupport::TestCase
  include DefinedWorkflowTestHelper

  setup { setup_defined_workflow }

  test "runs steps in order and fills each from the outputs before it, keeping a lone reference's type" do
    definition = {
      "steps" => [
        step("first", "echo", { "count" => "{{inputs.count}}", "region" => "{{inputs.region}}" }),
        step("second", "echo", { "copied" => "{{steps.first.count}}", "said" => "Count is {{steps.first.count}} in {{steps.first.region}}" })
      ],
      "edges" => [ edge("first", "second") ]
    }

    workflow = run_definition(definition, context: { "inputs" => { "count" => 3, "region" => "eu" } })

    assert workflow.succeeded?
    assert_equal 3, output_of(workflow, "second")["copied"]
    assert_equal "Count is 3 in eu", output_of(workflow, "second")["said"]
    assert_equal({ "copied" => 3, "said" => "Count is 3 in eu" }, workflow.steps.find_by!(name: "second").input)
  end

  test "keeps a snapshot of the definition, so changing the source after start changes nothing" do
    definition = { "steps" => [ step("only", "echo", { "said" => "before" }) ], "edges" => [] }
    TestDefinedWorkflow.held = true
    workflow = TestDefinedWorkflow.start!(@subject, definition: definition)
    definition["steps"].first["config"]["said"] = "after"

    TestDefinedWorkflow.held = false
    perform_enqueued_jobs { workflow.enqueue_next_steps }

    assert_equal "before", output_of(workflow.reload, "only")["said"]
    assert_equal "before", workflow.definition["steps"].first["config"]["said"]
  end

  test "one start key gives one run" do
    definition = { "steps" => [ step("only", "echo") ], "edges" => [] }

    first = TestDefinedWorkflow.start!(@subject, definition: definition, start_key: "run-1")
    again = TestDefinedWorkflow.start!(@subject, definition: definition, start_key: "run-1")

    assert_equal first.id, again.id
    assert_equal 1, SolidWorkflow::Workflow.where(start_key: "run-1").count
  end

  test "a class workflow started twice with one key is one run" do
    first = ExampleCalculationWorkflow.start!(@subject, context: { numbers: [ 1, 2 ] }, start_key: "calc-1")
    again = ExampleCalculationWorkflow.start!(@subject, context: { numbers: [ 1, 2 ] }, start_key: "calc-1")

    assert_equal first.id, again.id
  end

  test "refuses a definition it cannot run" do
    error = assert_raises(SolidWorkflow::InvalidDefinition) do
      TestDefinedWorkflow.start!(@subject, definition: { "steps" => [ step("a", "teleport") ], "edges" => [] })
    end
    assert_match "teleport", error.message
  end

  test "a branch runs the route whose condition holds and bypasses the others and what only they lead to" do
    definition = {
      "steps" => [
        step("check", "echo", { "verdict" => "problem" }),
        step("decide", "branch", { "routes" => [ { "route" => "ok", "when" => { "left" => "{{steps.check.verdict}}", "operator" => "equals", "right" => "ok" } },
                                                 { "route" => "bad", "when" => { "left" => "{{steps.check.verdict}}", "operator" => "equals", "right" => "problem" } } ],
                                   "otherwise" => "unsure" }),
        step("all_clear", "echo"),
        step("all_clear_note", "echo"),
        step("raise", "echo", { "about" => "{{steps.check.verdict}}" }),
        step("unsure", "echo"),
        step("finish", "echo")
      ],
      "edges" => [
        edge("check", "decide"), edge("decide", "all_clear", "ok"), edge("all_clear", "all_clear_note"),
        edge("decide", "raise", "bad"), edge("decide", "unsure", "unsure"),
        edge("all_clear_note", "finish"), edge("raise", "finish"), edge("unsure", "finish")
      ]
    }

    workflow = run_definition(definition)

    assert workflow.succeeded?
    assert_equal "bad", workflow.steps.find_by!(name: "decide").route
    assert_equal "succeeded", status_of(workflow, "raise")
    assert_equal "bypassed", status_of(workflow, "all_clear")
    assert_equal "bypassed", status_of(workflow, "all_clear_note")
    assert_equal "bypassed", status_of(workflow, "unsure")
    assert_equal "succeeded", status_of(workflow, "finish")
    assert workflow.events.exists?(event_type: SolidWorkflow::Events::Step::BYPASSED)
  end

  test "a branch with no condition holding takes its otherwise route" do
    definition = {
      "steps" => [
        step("decide", "branch", { "routes" => [ { "route" => "big", "when" => { "left" => 3, "operator" => "greater_than", "right" => 10 } } ], "otherwise" => "small" }),
        step("big_one", "echo"), step("small_one", "echo")
      ],
      "edges" => [ edge("decide", "big_one", "big"), edge("decide", "small_one", "small") ]
    }

    workflow = run_definition(definition)

    assert_equal "bypassed", status_of(workflow, "big_one")
    assert_equal "succeeded", status_of(workflow, "small_one")
  end

  test "a failed step that takes its error route runs that route and the run succeeds" do
    definition = {
      "steps" => [
        step("call", "fail", { "terminal" => true }, on_failure: "error_route"),
        step("next", "echo"), step("tell", "echo")
      ],
      "edges" => [ edge("call", "next"), edge("call", "tell", "error") ]
    }

    workflow = run_definition(definition)

    assert workflow.succeeded?
    assert_equal "failed", status_of(workflow, "call")
    assert_equal "bypassed", status_of(workflow, "next")
    assert_equal "succeeded", status_of(workflow, "tell")
  end

  test "a failed step set to carry on lets the steps after it run" do
    definition = { "steps" => [ step("call", "fail", { "terminal" => true }, on_failure: "continue"), step("next", "echo") ], "edges" => [ edge("call", "next") ] }

    workflow = run_definition(definition)

    assert workflow.succeeded?
    assert_equal "succeeded", status_of(workflow, "next")
  end

  test "a failed step that stops the run fails it and cancels the rest" do
    definition = { "steps" => [ step("call", "fail", { "terminal" => true }), step("next", "echo") ], "edges" => [ edge("call", "next") ] }

    workflow = run_definition(definition)

    assert workflow.failed?
    assert_equal "cancelled", status_of(workflow, "next")
  end

  test "a join of all hands on every route into it" do
    definition = {
      "steps" => [ step("a", "echo", { "n" => 1 }), step("b", "echo", { "n" => 2 }), step("both", "join", { "mode" => "all" }) ],
      "edges" => [ edge("a", "both"), edge("b", "both") ]
    }

    workflow = run_definition(definition)

    assert_equal({ "a" => { "n" => 1 }, "b" => { "n" => 2 } }, output_of(workflow, "both")["steps"])
  end

  test "a join of the first runs once one route into it arrives" do
    definition = {
      "steps" => [ step("fast", "echo"), step("gate", "wait_for_event", { "event" => "never" }, timeout_seconds: 600),
                   step("first", "join", { "mode" => "first" }), step("after", "echo") ],
      "edges" => [ edge("fast", "first"), edge("gate", "first"), edge("first", "after") ]
    }

    workflow = run_definition(definition)

    assert_equal "succeeded", status_of(workflow, "first")
    assert_equal "fast", output_of(workflow, "first")["first"]
    assert_equal "succeeded", status_of(workflow, "after")
    assert workflow.waiting?
  end

  test "hosts are told of every event" do
    run_definition({ "steps" => [ step("only", "echo") ], "edges" => [] })

    types = TestDefinedWorkflow.observed.map(&:second)
    assert_includes types, SolidWorkflow::Events::Workflow::STARTED
    assert_includes types, SolidWorkflow::Events::Step::SUCCEEDED
    assert_includes types, SolidWorkflow::Events::Workflow::SUCCEEDED
  end

  test "declared outputs are what a run hands back" do
    definition = { "steps" => [ step("only", "echo", { "n" => 4 }) ], "edges" => [], "outputs" => { "total" => "{{steps.only.n}}" } }

    assert_equal({ "total" => 4 }, run_definition(definition).result)
  end
end
