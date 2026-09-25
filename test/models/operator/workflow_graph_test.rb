require "test_helper"

class Operator::WorkflowGraphTest < ActiveSupport::TestCase
  Step = Struct.new(:name, :position, :depends_on)

  test "a step stands one column after the last step it waits for, and steps that run together share a column" do
    steps = [ Step.new("a", 0, []), Step.new("b", 1, [ "a" ]), Step.new("c", 2, [ "a" ]), Step.new("d", 3, [ "b", "c" ]), Step.new("e", 4, []) ]

    placed = Operator::WorkflowGraph.new(steps).nodes.to_h { |node| [ node.step.name, [ node.column, node.row ] ] }

    assert_equal({ "a" => [ 0, 0 ], "b" => [ 1, 0 ], "c" => [ 1, 1 ], "d" => [ 2, 0 ], "e" => [ 0, 1 ] }, placed)
  end
end
