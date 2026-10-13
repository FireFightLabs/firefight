require_relative "test_helper"

class SolidWorkflow::DefinitionTest < ActiveSupport::TestCase
  include DefinedWorkflowTestHelper

  def problems(data) = SolidWorkflow::Definition.new(data, action_kinds: %w[echo]).problems

  test "a well formed definition has no problems" do
    data = {
      "steps" => [ step("check", "echo"), step("decide", "branch", { "routes" => [ { "route" => "yes", "when" => { "left" => 1, "operator" => "equals", "right" => 1 } } ], "otherwise" => "no" }),
                   step("pause", "delay", { "minutes" => 5 }), step("each", "for_each", { "items" => [ 1 ], "steps" => [ step("inside", "echo") ], "edges" => [] }) ],
      "edges" => [ edge("check", "decide"), edge("decide", "pause", "yes"), edge("decide", "each", "no") ]
    }

    assert_empty problems(data)
  end

  test "names each problem it finds" do
    assert_includes problems({ "steps" => [] }), "A workflow needs at least one step."
    assert_match "not a kind of step", problems({ "steps" => [ step("a", "teleport") ] }).join
    assert_match "used more than once", problems({ "steps" => [ step("a", "echo"), step("a", "echo") ] }).join
    assert_match "names a step that is not in the workflow", problems({ "steps" => [ step("a", "echo") ], "edges" => [ edge("a", "ghost") ] }).join
    assert_match "loop back", problems({ "steps" => [ step("a", "echo"), step("b", "echo") ], "edges" => [ edge("a", "b"), edge("b", "a") ] }).join
    assert_match "needs a time limit", problems({ "steps" => [ step("a", "wait_for_event", { "event" => "x" }) ] }).join
    assert_match "needs an error route", problems({ "steps" => [ step("a", "echo", {}, on_failure: "error_route") ] }).join
    assert_match "no route called maybe", problems({ "steps" => [ step("a", "branch", { "routes" => [ { "route" => "yes", "when" => { "left" => 1, "operator" => "is_empty" } } ] }), step("b", "echo") ],
                                                     "edges" => [ edge("a", "b", "maybe") ] }).join
    assert_match "exactly one", problems({ "steps" => [ step("a", "delay", { "minutes" => 1, "until" => "09:00" }) ] }).join
    assert_match "at least two routes", problems({ "steps" => [ step("a", "echo"), step("b", "join") ], "edges" => [ edge("a", "b") ] }).join
    assert_match "between 1 and", problems({ "steps" => [ step("a", "for_each", { "items" => [], "concurrency" => 0, "steps" => [ step("b", "echo") ] }) ] }).join
  end

  test "a name inside a for each is unique across the whole workflow" do
    data = { "steps" => [ step("look", "echo"), step("each", "for_each", { "items" => [], "steps" => [ step("look", "echo") ], "edges" => [] }) ], "edges" => [] }

    assert_match "used more than once", problems(data).join
  end

  test "problems are sentences without dashes or semicolons" do
    found = problems({ "steps" => [ step("a", "teleport"), step("a", "wait_for_event") ], "edges" => [ edge("a", "ghost") ] })

    found.each do |sentence|
      assert sentence.end_with?("."), sentence
      assert_no_match(/[;—–]/, sentence)
    end
  end

  test "conditions compare numbers as numbers and combine" do
    assert SolidWorkflow::Condition.met?({ "left" => "10", "operator" => "greater_than", "right" => 9 })
    assert SolidWorkflow::Condition.met?({ "left" => "web", "operator" => "is_one_of", "right" => %w[api web] })
    assert SolidWorkflow::Condition.met?({ "all" => [ { "left" => "a", "operator" => "starts_with", "right" => "a" }, { "not" => { "left" => "", "operator" => "is_not_empty" } } ] })
    assert SolidWorkflow::Condition.met?({ "any" => [ { "left" => [ 1, 2 ], "operator" => "contains", "right" => 2 }, { "left" => 1, "operator" => "equals", "right" => 3 } ] })
    assert_not SolidWorkflow::Condition.met?({ "left" => "x", "operator" => "matches_regex", "right" => "(" })
    assert SolidWorkflow::Condition.well_formed?({ "left" => "x", "operator" => "is_empty" })
    assert_not SolidWorkflow::Condition.well_formed?({ "left" => "x", "operator" => "teleport", "right" => 1 })
  end
end
