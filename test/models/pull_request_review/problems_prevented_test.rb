require "test_helper"

class PullRequestReview::ProblemsPreventedTest < ActiveSupport::TestCase
  include PreventedProblemHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "counts serious or major and worse findings fixed before their pull request merged in the window, and nothing else" do
    merged = reviewed_pull_request!(@workspace, number: 1, merged_at: 2.days.ago)
    major = review_finding!(merged, fixed_at: 3.days.ago)
    critical = review_finding!(merged, claim: "Lock the order first", severity: PullRequestReview::Finding::SEVERITY_CRITICAL, fixed_at: 3.days.ago)
    serious_minor = review_finding!(merged, claim: "Keep the retry", severity: PullRequestReview::Finding::SEVERITY_MINOR, serious: true, fixed_at: 3.days.ago)
    review_finding!(merged, claim: "A minor point", severity: PullRequestReview::Finding::SEVERITY_MINOR, fixed_at: 3.days.ago)
    review_finding!(merged, claim: "Still open")
    review_finding!(merged, claim: "Fixed after the merge", fixed_at: 1.day.ago)
    review_finding!(reviewed_pull_request!(@workspace, number: 2, merged_at: nil), fixed_at: 1.day.ago)
    review_finding!(reviewed_pull_request!(@workspace, number: 3, merged_at: 40.days.ago), fixed_at: 41.days.ago)
    review_finding!(reviewed_pull_request!(@workspace, number: 4, merged_at: 1.day.ago, rehearsal: true), fixed_at: 2.days.ago)
    review_finding!(reviewed_pull_request!(workspaces(:slack_workspace_two), number: 5, merged_at: 1.day.ago), fixed_at: 2.days.ago)

    prevented = PullRequestReview::ProblemsPrevented.new(@workspace, days: 30)

    assert_equal 3, prevented.count
    assert_equal [ major, critical, serious_minor ].map(&:id), prevented.page(1).problems.map(&:id)
    assert_equal 4, PullRequestReview::ProblemsPrevented.new(@workspace, days: 90).count, "the older merge is in a longer window"
  end

  test "pages run newest merge first, and say whether another follows" do
    older = reviewed_pull_request!(@workspace, number: 1, merged_at: 5.days.ago)
    newer = reviewed_pull_request!(@workspace, number: 2, merged_at: 1.day.ago)
    (PullRequestReview::ProblemsPrevented::PER_PAGE + 1).times { |index| review_finding!(older, claim: "Problem #{index}", fixed_at: 6.days.ago) }
    newest = review_finding!(newer, claim: "Newest", fixed_at: 2.days.ago)

    prevented = PullRequestReview::ProblemsPrevented.new(@workspace)
    first = prevented.page(nil)
    second = prevented.page(2)

    assert_equal [ 1, 2, nil ], [ first.number, first.next_page, first.previous_page ]
    assert_equal newest, first.problems.first
    assert_equal PullRequestReview::ProblemsPrevented::PER_PAGE, first.problems.size
    assert_equal [ 2, nil, 1 ], [ second.number, second.next_page, second.previous_page ]
    assert_equal 2, second.problems.size
    assert_equal prevented.count, (first.problems + second.problems).map(&:id).uniq.size
  end

  test "an unknown window falls back to thirty days" do
    assert_equal 30, PullRequestReview::ProblemsPrevented.new(@workspace, days: "12").days
  end
end
