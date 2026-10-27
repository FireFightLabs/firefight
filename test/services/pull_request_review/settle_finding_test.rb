require "test_helper"

class PullRequestReview::SettleFindingTest < ActiveSupport::TestCase
  test "a settlement keeps or drops with a reason, and names only earlier findings that are listed, each with an outcome and a note" do
    tool = PullRequestReview::SettleFinding.new([ 1, 2 ])

    assert_match "verdict is keep or drop", tool.call(verdict: "maybe", reason: "x")
    assert_match "There is no earlier finding 3.", tool.call(verdict: "keep", reason: "Holds.", earlier: [ { "finding" => 3, "outcome" => "confirm", "note" => "x" } ])
    assert_match "Finding 1 needs an outcome and a note.", tool.call(verdict: "keep", reason: "Holds.", earlier: [ { "finding" => 1, "outcome" => "withdraw" } ])
    assert_match "Finding 1 is named more than once. Say one outcome for it.",
                 tool.call(verdict: "keep", reason: "Holds.", earlier: [ { "finding" => 1, "outcome" => "confirm", "note" => "Seen." },
                                                                         { "finding" => 1, "outcome" => "withdraw", "note" => "Wrong." } ])
    assert_not tool.settled?

    assert_equal "Settled.", tool.call(verdict: "drop", reason: "The guard on line 4 handles it.", earlier: [ { "finding" => 2, "outcome" => "confirm", "note" => "Seen." } ])
    assert_not tool.settled.keep?
    assert_equal [ 2, "confirm" ], [ tool.settled.earlier.sole.number, tool.settled.earlier.sole.outcome ]
  end
end
