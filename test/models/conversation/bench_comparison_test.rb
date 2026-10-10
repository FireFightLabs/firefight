require "test_helper"

class Conversation::BenchComparisonTest < ActiveSupport::TestCase
  test "a drop larger than the noise between two replays fails, and the worst scenarios are named first" do
    comparison = compare({ "a" => 1.0, "b" => 1.0 }, { "a" => 0.5, "b" => 1.0 })

    assert comparison.dropped?
    assert_equal [ "a" ], comparison.worse.map(&:scenario)
    assert_equal(-0.5, comparison.rows.first.delta)
  end

  test "a drop between two models says how they differ, so it never fails a change" do
    base = export("a" => 1.0)
    head = export("a" => 0.2).merge("model" => "claude-sonnet-5")
    comparison = Conversation::BenchComparison.from_exports(base, head)

    assert comparison.dropped?
    refute comparison.comparable?
    refute comparison.failed?
    assert Conversation::BenchComparison.from_exports(base, export("a" => 0.2)).failed?
  end

  test "a drop within the noise holds" do
    comparison = compare({ "a" => 0.8, "b" => 0.8 }, { "a" => 0.76, "b" => 0.8 })

    refute comparison.dropped?
    assert_empty comparison.worse
  end

  test "only scenarios both runs scored count, so adding one never moves the comparison" do
    comparison = compare({ "a" => 0.9 }, { "a" => 0.9, "new" => 0.1 })

    refute comparison.dropped?
    assert_equal 0.9, comparison.head_total
    assert_equal %w[a new], comparison.rows.map(&:scenario)
    refute comparison.rows.last.both?
  end

  test "a scenario that could not finish is left out rather than counted as zero" do
    base = export("a" => 0.9)
    head = export("a" => 0.9)
    head["scenarios"]["a"]["status"] = Conversation::BenchResult::STATUS_ERRORED

    refute Conversation::BenchComparison.from_exports(base, head).dropped?
  end

  test "a run's export reads back as the same scores" do
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_CI, prompt_version: "v1", model: "gpt-4o")
    run.results.create!(workspace: workspaces(:slack_workspace_one), scenario: "a", title: "A", status: Conversation::BenchResult::STATUS_SCORED,
                        right: 1.0, moved_forward: 0.5, asked_when_needed: 1.0, cost: 1.0, total: 0.875)

    exported = JSON.parse(Conversation::BenchComparison.export(run).to_json)
    comparison = Conversation::BenchComparison.from_exports(exported, exported)

    assert_equal 0.875, comparison.head_total
    assert_equal 0.5, comparison.dimension(:head, :moved_forward)
  end

  private

  def compare(base, head) = Conversation::BenchComparison.from_exports(export(base), export(head))

  def export(totals)
    {
      "model" => "gpt-4o",
      "scenarios" => totals.to_h do |key, total|
        [ key, { "title" => key, "status" => Conversation::BenchResult::STATUS_SCORED, "right" => total, "moved_forward" => total,
                 "asked_when_needed" => total, "cost" => total } ]
      end
    }
  end
end
