require "application_system_test_case"

class OperatorHalonBenchTest < ApplicationSystemTestCase
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "an operator ticks two runs, compares them, and reads the scenario that dropped" do
    run_on(2.days.ago, "a1b2c3d4e5f6", [ 1.0, 1.0, 1.0, 1.0 ])
    newer = run_on(1.hour.ago, "f6e5d4c3b2a1", [ 0.5, 0.5, 1.0, 1.0 ])

    visit operator_halon_benches_path
    assert_text "Chat bench"
    all("button[role=checkbox]").first(2).each(&:click)
    click_button "Compare"

    assert_text "Compare bench runs"
    assert_text "The newer run dropped by more than 0.05"
    assert_text "A person says no once, and Halon never offers again"

    visit operator_halon_bench_path(newer)
    assert_text "Never called rollback."
    click_link "Compare with the run before"
    assert_text "Compare bench runs"
  end

  test "the Run dialog offers Halon's model by default" do
    visit operator_halon_benches_path
    click_button "Run"

    assert_text "Run the chat bench"
    assert_text "Halon's model"
  end

  private

  def run_on(at, version, scores)
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_CI, label: "main",
                                         prompt_version: version, model: "claude-sonnet-5", status: Conversation::BenchRun::STATUS_FINISHED,
                                         created_at: at, finished_at: at)
    score = Conversation::BenchScore.new(*scores)
    run.results.create!(workspace: @workspace, scenario: "sticks_with_no", title: Conversation::BenchCase.scenario("sticks_with_no").title,
                        status: Conversation::BenchResult::STATUS_SCORED, **score.to_h, total: score.total,
                        notes: score.total < 1 ? [ "Never called rollback." ] : [])
    run
  end
end
