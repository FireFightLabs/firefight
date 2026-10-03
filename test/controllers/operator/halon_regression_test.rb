require "test_helper"

class Operator::HalonRegressionTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(halon_regression_enabled: true)
    original = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                 max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED)
    @finding = original.create_finding!(summary: "The disk on db-1 filled", outcome: Investigation::Finding::OUTCOME_CONFIRMED, outcome_at: Time.current)
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "only a verified operator reaches regression runs" do
    sign_in(users(:bob), @workspace)

    get operator_halon_regressions_path, headers: inertia_headers
    assert_response :not_found
    post operator_halon_regressions_path
    assert_response :not_found
  end

  test "an operator runs the set on a model, and a case that passed before and fails now is listed first" do
    as_operator
    FirefightAi.stubs(:priced_chat_models).returns([ registry_model("claude-sonnet-5", "Claude Sonnet 5", "anthropic") ])
    before = Investigation::RegressionRun.create!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR, prompt_version: "abc", model: "claude-sonnet-5",
                                                  provider: "anthropic", status: Investigation::RegressionRun::STATUS_FINISHED, created_at: 1.day.ago)
    before.results.create!(finding: @finding, expected: "confirmed", status: Investigation::RegressionResult::STATUS_PASSED)

    post operator_halon_regressions_path, params: { model: "claude-sonnet-5" }

    run = Investigation::RegressionRun.find_by!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR, started_by: @operator)
    assert_redirected_to operator_halon_regression_path(run)
    assert_equal "Replaying 1 rated answer on Claude Sonnet 5.", flash[:notice]
    assert_equal [ "claude-sonnet-5", "anthropic" ], [ run.model, run.provider ]

    run.results.sole.settle!(status: Investigation::RegressionResult::STATUS_FAILED, reason: "Different cause.")
    get operator_halon_regression_path(run), headers: inertia_headers

    entry = inertia_props["cases"].sole
    assert_equal [ "failed", "passed", true ], [ entry["status"], entry["previousStatus"], entry["newlyFailing"] ]
    assert_equal 1, inertia_props["run"]["failed"]
  end

  test "the list says what a run would test, and a model Firefight cannot price is refused" do
    as_operator
    FirefightAi.stubs(:priced_chat_models).returns([])

    get operator_halon_regressions_path, headers: inertia_headers
    assert_equal 1, inertia_props["casesAvailable"]
    assert_equal FirefightAi::Investigator.prompt_version, inertia_props["promptVersion"]

    post operator_halon_regressions_path, params: { model: "made-up" }
    assert_redirected_to operator_halon_regressions_path
    assert_not Investigation::RegressionRun.exists?
  end

  test "a second run waits until the one going has finished" do
    as_operator
    Investigation::RegressionRun.create!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR, prompt_version: "abc")

    get operator_halon_regressions_path, headers: inertia_headers
    assert_equal "A regression run is still going. Start another once it finishes.", inertia_props["runBlockedReason"]

    assert_no_difference -> { Investigation::RegressionRun.count } do
      post operator_halon_regressions_path
    end
    assert_equal "A regression run is still going. Start another once it finishes.", flash[:alert]
  end

  private

  RegistryModel = Struct.new(:id, :name, :provider)

  def registry_model(id, name, provider) = RegistryModel.new(id, name, provider)

  def as_operator
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end
end
