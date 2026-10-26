require "application_system_test_case"

class HalonPerformanceTest < ApplicationSystemTestCase
  include PreventedProblemHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
  end

  test "a member opens Performance from the sidebar, reads the record, and narrows the window" do
    [ [ "confirmed", 3.days.ago ], [ "confirmed", 10.days.ago ], [ "partial", 12.days.ago ], [ nil, 2.days.ago ], [ "wrong", 1.day.ago ], [ "wrong", 20.days.ago ] ].each do |outcome, at|
      run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                              status: Investigation::STATUS_SUCCEEDED, created_at: at, started_at: at, completed_at: at + 4.minutes)
      run.create_finding!(summary: outcome == "wrong" ? "The deploy at 14:02 broke checkout" : "The disk on db-1 filled", outcome: outcome, outcome_at: (at + 1.hour if outcome))
    end
    Chat::Memory.learn!(@workspace, text: "A 5xx on checkout after a deploy has meant a full disk on db-1", subject: nil, source: @incident)

    visit dashboard_path
    click_link "Performance"

    assert_text "Nothing here is estimated."
    assert_text "5 of 6 answers rated"
    assert_text "A 5xx on checkout after a deploy has meant a full disk on db-1"
    page.save_screenshot(Rails.root.join("tmp/screenshots/halon-performance.png"))

    click_button "7 days"
    assert_text "2 of 3 answers rated"
  end

  test "a workspace Halon has not worked in yet says so" do
    visit halon_performance_path
    assert_text "Halon has not investigated anything in the last 30 days."
    assert_text "0 risky changes caught in the last 30 days"
    assert_text "No pull request merged in the last 30 days with a serious or major finding fixed first."
  end

  test "a member opens each problem Halon's reviews prevented, and shows more when there are many" do
    review = reviewed_pull_request!(@workspace, number: 812, merged_at: 2.days.ago)
    (PullRequestReview::ProblemsPrevented::PER_PAGE + 1).times { |index| review_finding!(review, claim: "Problem #{index}", fixed_at: 3.days.ago) }

    visit halon_performance_path

    assert_text "#{PullRequestReview::ProblemsPrevented::PER_PAGE + 1} risky changes caught in the last 30 days"
    within(find("li", text: "Problem 0", match: :first)) do
      assert_link "acme/checkout #812", href: "https://github.com/acme/checkout/pull/812"
      assert_link "Open the comment on the pull request", href: "https://github.com/acme/checkout/pull/812#discussion_r4253331341"
      click_button "Show how it would have failed"
      assert_text "Customers are charged twice, as in INC-012"
      assert_link "INC-012 Double charges at checkout"
      assert_text "config/payments.yml:4, fixed in 1cb47a9"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/halon-prevented.png"))
    assert_no_text "Problem #{PullRequestReview::ProblemsPrevented::PER_PAGE}"

    click_button "Show more"

    assert_text "Problem #{PullRequestReview::ProblemsPrevented::PER_PAGE}"
    assert_no_button "Show more"

    click_button "7 days"
    assert_text "#{PullRequestReview::ProblemsPrevented::PER_PAGE + 1} risky changes caught in the last 7 days"
    assert_no_text "Problem #{PullRequestReview::ProblemsPrevented::PER_PAGE}"
    assert_button "Show more"
  end
end
