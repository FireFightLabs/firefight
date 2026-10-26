require "test_helper"

class HalonPerformanceControllerTest < ActionDispatch::IntegrationTest
  include PreventedProblemHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    run = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10,
                                            max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED, started_at: 1.hour.ago, completed_at: 55.minutes.ago)
    run.create_finding!(summary: "The deploy did it", outcome: Investigation::Finding::OUTCOME_WRONG, outcome_at: 50.minutes.ago)
  end

  test "any member sees how Halon has done, over the window asked for" do
    sign_in(users(:bob), @workspace)

    get halon_performance_path(days: 7), headers: inertia_headers

    assert_response :success
    performance = inertia_props["performance"]
    assert_equal [ 7, 1, 1 ], [ performance["days"], performance["answered"], performance["wrong"] ]
    assert_equal "The deploy did it", performance["mistakes"].sole["summary"]
    assert_equal Investigation::Performance::WINDOWS, inertia_props["windows"]
  end

  test "a wrong answer to a question asked in Slack is named by the question as Slack shows it" do
    sign_in(users(:bob), @workspace)
    bob = workspace_memberships(:bob_workspace_one)
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED,
      started_at: 2.hours.ago, completed_at: 110.minutes.ago,
      brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => "<@#{bob.platform_user_id}> says *checkout* is slow" },
                                       source: Investigation::Brief::SOURCE_COMMAND)
    )
    run.create_finding!(summary: "The cache did it", outcome: Investigation::Finding::OUTCOME_WRONG, outcome_at: 100.minutes.ago)

    get halon_performance_path(days: 7), headers: inertia_headers

    mistake = inertia_props["performance"]["mistakes"].find { |shown| shown["summary"] == "The cache did it" }
    assert_equal "@#{bob.display_name} says checkout is slow", mistake["label"]
  end

  test "the problems Halon's reviews prevented are counted for the window, each with its pull request, how it fails and its comment" do
    sign_in(users(:bob), @workspace)
    review = reviewed_pull_request!(@workspace, number: 812, merged_at: 2.days.ago)
    review_finding!(review, fixed_at: 3.days.ago)
    review_finding!(reviewed_pull_request!(@workspace, number: 700, merged_at: 20.days.ago), fixed_at: 21.days.ago)

    get halon_performance_path(days: 7), headers: inertia_headers

    assert_equal 1, inertia_props["preventedCount"]
    problem = inertia_props[HalonPerformanceController::PROP_PREVENTED].sole
    assert_equal [ "acme/checkout", 812, "https://github.com/acme/checkout/pull/812" ], problem.values_at("repository", "number", "pullRequestUrl")
    assert_equal [ "Stability & Availability", "Major", "Keep the payment timeout above the gateway's" ], problem.values_at("category", "severity", "claim")
    assert_equal "Customers are charged twice, as in INC-012", problem["failureChain"].last
    assert_equal [ PullRequestReview::Finding::EVIDENCE_INCIDENT, "https://app.example.com/incidents/12" ], problem["evidence"].first.values_at("kind", "url")
    assert_equal "https://github.com/acme/checkout/pull/812#discussion_r4253331341", problem["commentUrl"]

    get halon_performance_path(days: 30), headers: inertia_headers
    assert_equal 2, inertia_props["preventedCount"]
  end

  test "prevented problems load a page at a time, and say when there is another" do
    sign_in(users(:bob), @workspace)
    review = reviewed_pull_request!(@workspace, number: 812, merged_at: 2.days.ago)
    (PullRequestReview::ProblemsPrevented::PER_PAGE + 1).times { |index| review_finding!(review, claim: "Problem #{index}", fixed_at: 3.days.ago) }

    get halon_performance_path, headers: inertia_headers
    assert_equal PullRequestReview::ProblemsPrevented::PER_PAGE, inertia_props["prevented"].size
    assert_equal 2, response.parsed_body.dig("scrollProps", "prevented", "nextPage")

    get halon_performance_path(HalonPerformanceController::PREVENTED_PAGE_PARAM => 2), headers: inertia_headers.merge(
      "X-Inertia-Partial-Component" => "halon/performance", "X-Inertia-Partial-Data" => "prevented"
    )
    assert_equal "Problem #{PullRequestReview::ProblemsPrevented::PER_PAGE}", inertia_props["prevented"].sole["claim"]
    assert_nil response.parsed_body.dig("scrollProps", "prevented", "nextPage")
  end

  test "a workspace without Halon is sent back with why" do
    sign_in(users(:alice), @workspace)
    Investigation.stubs(:available_for?).returns(false)

    get halon_performance_path

    assert_redirected_to dashboard_path
  end
end
