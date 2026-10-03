require "test_helper"

class Investigation::PerformanceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "counts runs, answers, and what the team said of them, never a rehearsal and never outside the window" do
    run!(outcome: Investigation::Finding::OUTCOME_CONFIRMED, seconds: 120)
    run!(outcome: Investigation::Finding::OUTCOME_CONFIRMED, seconds: 240)
    run!(outcome: Investigation::Finding::OUTCOME_WRONG, seconds: 600)
    run!(outcome: nil, seconds: 60)
    run!(outcome: nil, summary: nil, status: Investigation::STATUS_FAILED)
    run!(outcome: Investigation::Finding::OUTCOME_WRONG, rehearsal: true)
    run!(outcome: Investigation::Finding::OUTCOME_WRONG, created_at: 40.days.ago)

    performance = Investigation::Performance.new(@workspace, days: 30)

    assert_equal [ 5, 5, 4, 3 ], [ performance.runs_count, performance.ended_count, performance.answered_count, performance.rated_count ]
    assert_equal({ "confirmed" => 2, "partial" => 0, "wrong" => 1, "not_rated" => 1 }, performance.verdicts)
    assert_equal 180, performance.median_seconds
    assert_equal 4, performance.weeks.sum { |week| week.confirmed + week.partial + week.wrong + week.not_rated }
    assert_equal 2, Investigation::Performance.new(@workspace, days: 90).verdicts["wrong"], "the older wrong answer is in a longer window"
  end

  test "a fix counts once, as undone when its undo went through, otherwise by how it ended" do
    applied = fix!(Investigation::RemediationPlan::STATUS_APPLIED)
    undone = fix!(Investigation::RemediationPlan::STATUS_APPLIED)
    Investigation::RemediationPlan.create!(finding: undone.finding, undoes: undone, summary: "Reverse it", status: Investigation::RemediationPlan::STATUS_APPLIED)
    fix!(Investigation::RemediationPlan::STATUS_CANCELLED)
    fix!(Investigation::RemediationPlan::STATUS_PROPOSED)

    fixes = Investigation::Performance.new(@workspace).fixes

    assert_equal({ proposed: 4, applied: 1, undone: 1, cancelled: 1 }, fixes.to_h)
    assert applied
  end

  test "an answer marked wrong comes with the lessons its incident taught, never a rejected one" do
    finding = run!(outcome: Investigation::Finding::OUTCOME_WRONG)
    kept = Chat::Memory.learn!(@workspace, text: "A 5xx after a deploy has meant a full disk", subject: nil, source: @incident).memory
    rejected = Chat::Memory.learn!(@workspace, text: "Deploys break checkout", subject: nil, source: @incident).memory
    rejected.reject!(by: workspace_memberships(:alice_workspace_one), reason: "No")

    mistake = Investigation::Performance.new(@workspace).mistakes.sole

    assert_equal finding, mistake.finding
    assert_equal [ kept ], mistake.lessons
  end

  test "a window it does not offer falls back to thirty days" do
    assert_equal 30, Investigation::Performance.new(@workspace, days: "365").days
    assert_equal 7, Investigation::Performance.new(@workspace, days: "7").days
  end

  test "a run still working is not answered even once it has written its finding, and with no answer there is no median" do
    run!(outcome: nil, status: Investigation::STATUS_RUNNING)

    performance = Investigation::Performance.new(@workspace)

    assert_equal [ 1, 0, 0 ], [ performance.runs_count, performance.ended_count, performance.answered_count ]
    assert_nil performance.median_seconds
  end

  test "an undo not yet applied leaves its fix counted as applied" do
    fix = fix!(Investigation::RemediationPlan::STATUS_APPLIED)
    Investigation::RemediationPlan.create!(finding: fix.finding, undoes: fix, summary: "Reverse it", status: Investigation::RemediationPlan::STATUS_PROPOSED)

    assert_equal({ proposed: 1, applied: 1, undone: 0, cancelled: 0 }, Investigation::Performance.new(@workspace).fixes.to_h)
  end

  test "lessons and runs from another workspace never appear" do
    run!(outcome: Investigation::Finding::OUTCOME_WRONG)
    other = workspaces(:slack_workspace_two)
    Chat::Memory.create!(workspace: other, text: "Somebody else's lesson", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)

    performance = Investigation::Performance.new(@workspace)

    assert_empty performance.mistakes.sole.lessons
    assert_equal 0, Investigation::Performance.new(other).runs_count
  end

  private

  def run!(outcome:, summary: "The disk filled", seconds: 90, status: Investigation::STATUS_SUCCEEDED, rehearsal: false, created_at: 1.day.ago)
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                            status: status, rehearsal: rehearsal, created_at: created_at,
                                            started_at: created_at, completed_at: created_at + seconds)
    run.create_finding!(summary: summary, outcome: outcome, outcome_at: (created_at if outcome))
  end

  def fix!(status)
    Investigation::RemediationPlan.create!(finding: run!(outcome: nil), summary: "Roll back", status: status)
  end
end
