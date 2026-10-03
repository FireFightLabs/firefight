require "application_system_test_case"

class OperatorHalonRegressionTest < ApplicationSystemTestCase
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(halon_regression_enabled: true)
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
    @incident = incidents(:active_critical_ws1)
    original = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                                 status: Investigation::STATUS_SUCCEEDED)
    @finding = original.create_finding!(summary: "The disk on db-1 filled", outcome: Investigation::Finding::OUTCOME_CONFIRMED, outcome_at: 1.day.ago)
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "an operator opens a regression run from the list and reads the case that now fails first" do
    before = run_on(2.days.ago, Investigation::RegressionResult::STATUS_PASSED)
    run = run_on(1.hour.ago, Investigation::RegressionResult::STATUS_FAILED, answer: "The deploy at 14:02 did it", reason: "The first blames the disk, the second the deploy.")

    visit operator_halon_regressions_path
    assert_text "Settings, Workspace, Halon"
    assert_text "New prompt deployed"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-regression.png"))

    find("a[href='#{operator_halon_regression_path(run)}']").click
    assert_text "passed in the run before"
    assert_text "Passed before"
    assert_text "The deploy at 14:02 did it"
    assert_text "The first blames the disk, the second the deploy."
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-regression-run.png"))
    assert before
  end

  test "the Run dialog offers Halon's model by default" do
    visit operator_halon_regressions_path
    click_button "Run"

    assert_text "Run the regression set"
    assert_text "Replays the latest rated answer on the model you choose"
    assert_text "Halon's model"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-regression-dialog.png"))
  end

  private

  def run_on(at, status, **columns)
    run = Investigation::RegressionRun.create!(trigger: Investigation::RegressionRun::TRIGGER_PROMPT_CHANGE, prompt_version: SecureRandom.hex(6),
                                               status: Investigation::RegressionRun::STATUS_FINISHED, created_at: at, finished_at: at)
    run.results.create!(finding: @finding, expected: Investigation::Finding::OUTCOME_CONFIRMED, status: status, finished_at: at, **columns)
    run
  end
end
