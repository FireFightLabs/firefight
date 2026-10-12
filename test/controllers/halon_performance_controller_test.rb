require "test_helper"

class HalonPerformanceControllerTest < ActionDispatch::IntegrationTest
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

  test "a workspace without Halon is sent back with why" do
    sign_in(users(:alice), @workspace)
    Investigation.stubs(:available_for?).returns(false)

    get halon_performance_path

    assert_redirected_to dashboard_path
  end
end
