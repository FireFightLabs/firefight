require "test_helper"

class Operator::HalonBenchTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  BENCH_KEYS = { "HALON_BENCH_OPENAI_API_KEY" => "sk-bench", "HALON_BENCH_ANTHROPIC_API_KEY" => "sk-bench" }.freeze

  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @previous_keys = BENCH_KEYS.keys.index_with { |name| ENV[name] }
    ENV.update(BENCH_KEYS)
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi.stubs(:deployment_model_for).with(AiPurpose::INVESTIGATION).returns(FirefightAi::ModelChoice.new(model: "gpt-4o"))
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
    @previous_keys.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  test "without a key of the bench's own, Run is refused and says which variable to set" do
    as_operator
    BENCH_KEYS.each_key { |name| ENV.delete(name) }

    get operator_halon_benches_path, headers: inertia_headers
    assert_match "HALON_BENCH_<PROVIDER>_API_KEY", inertia_props["runBlockedReason"]

    ENV["HALON_BENCH_ANTHROPIC_API_KEY"] = "sk-bench"
    post operator_halon_benches_path
    assert_redirected_to operator_halon_benches_path
    assert_equal "The bench pays with its own key, never the app's. Set HALON_BENCH_OPENAI_API_KEY to run gpt-4o.", flash[:alert]
    assert_not Conversation::BenchRun.exists?
  end

  test "only a verified operator reaches the bench" do
    sign_in(users(:bob), @workspace)

    get operator_halon_benches_path, headers: inertia_headers
    assert_response :not_found
    post operator_halon_benches_path
    assert_response :not_found
    get compare_operator_halon_benches_path(base: "a", head: "b"), headers: inertia_headers
    assert_response :not_found
  end

  test "an operator runs every scenario on a model as often and up to the budget they chose, and is told so" do
    as_operator
    FirefightAi.stubs(:priced_chat_models).returns([ registry_model("claude-sonnet-5", "Claude Sonnet 5", "anthropic") ])

    assert_enqueued_jobs Conversation::BenchCase.scenarios.size * 2, only: HalonBenchCaseJob do
      post operator_halon_benches_path, params: { model: "claude-sonnet-5", provider: "anthropic", repeats: 2, budget: "5.50" }
    end

    run = Conversation::BenchRun.find_by!(started_by: @operator)
    assert_redirected_to operator_halon_bench_path(run)
    assert_equal "Replaying #{Conversation::BenchCase.scenarios.size} scenarios 2 times each on Claude Sonnet 5, up to $5.50.", flash[:notice]
    assert_equal [ "claude-sonnet-5", "anthropic", Conversation::BenchRun::TRIGGER_OPERATOR ], [ run.model, run.provider, run.trigger ]
    assert_equal [ 2, 5_500_000 ], [ run.repeats, run.budget_micros ]
  end

  test "left on Halon's model the run uses the deployment's own, three times over and up to two dollars" do
    as_operator

    get operator_halon_benches_path, headers: inertia_headers
    assert_equal [ 3, 5, 2 ], inertia_props.values_at("defaultRepeats", "maxRepeats", "defaultBudget")
    post operator_halon_benches_path

    run = Conversation::BenchRun.find_by!(started_by: @operator)
    assert_equal "gpt-4o", run.model
    assert_equal "Replaying #{Conversation::BenchCase.scenarios.size} scenarios 3 times each on Halon's model, up to $2.00.", flash[:notice]
  end

  test "a number of repeats or a budget the bench cannot take is refused with the reason, and nothing starts" do
    as_operator

    post operator_halon_benches_path, params: { repeats: 9 }
    assert_redirected_to operator_halon_benches_path
    assert_equal "Each scenario is replayed from 1 to 5 times.", flash[:alert]

    post operator_halon_benches_path, params: { budget: "0" }
    assert_equal "The budget must be more than nothing.", flash[:alert]
    assert_not Conversation::BenchRun.exists?
  end

  test "a model Firefight cannot price is refused, and a second run waits until the one going has finished" do
    as_operator
    FirefightAi.stubs(:priced_chat_models).returns([])

    post operator_halon_benches_path, params: { model: "made-up" }
    assert_redirected_to operator_halon_benches_path
    assert_equal "That model is not one Firefight can price, so choose another.", flash[:alert]
    assert_not Conversation::BenchRun.exists?

    finished_run(at: 1.hour.ago).update!(status: Conversation::BenchRun::STATUS_RUNNING)
    get operator_halon_benches_path, headers: inertia_headers
    assert_equal "A bench run is still going. Start another once it finishes.", inertia_props["runBlockedReason"]
    assert_no_difference -> { Conversation::BenchRun.count } do
      post operator_halon_benches_path
    end
    assert_equal "A bench run is still going. Start another once it finishes.", flash[:alert]
  end

  test "the list shows each run's means, and a real chat's replay never appears among them" do
    as_operator
    run = finished_run(at: 1.hour.ago, totals: { "release" => [ 1.0, 0.5, 1.0, 1.0 ], "flaky" => [ 0.0, 0.5, 1.0, 1.0 ] })
    Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_CHAT, trigger: Conversation::BenchRun::TRIGGER_TERMINAL, prompt_version: "v1", model: "gpt-4o")

    get operator_halon_benches_path, headers: inertia_headers

    listed = inertia_props["runs"].sole
    assert_equal run.id, listed["id"]
    assert_equal [ 0.75, 0.5, 0.5, 2 ], [ listed["total"], listed["right"], listed["movedForward"], listed["scored"] ]
    assert_equal [ 0.667, 1.0 ], [ listed["quality"], listed["cost"] ]
    assert_equal Conversation::BenchCase.scenarios.size, inertia_props["scenarioCount"]
  end

  test "a run replayed more than once shows each scenario's mean and spread, how many agree, and every replay" do
    as_operator
    run = finished_run(at: 1.hour.ago, totals: { "release" => [ 1.0, 1.0, 1.0, 1.0 ] })
    run.update!(repeats: 2)
    run.results.create!(workspace: @workspace, scenario: "release", title: "Release", attempt: 2, status: Conversation::BenchResult::STATUS_SCORED,
                        right: 0.0, moved_forward: 1.0, asked_when_needed: 1.0, cost: 1.0, cited: 0.0, total: 0.75, notes: [ "Cited none of the evidence a right answer links to." ])

    get operator_halon_bench_path(run), headers: inertia_headers

    scenario = inertia_props["scenarios"].sole
    assert_equal [ 0.875, 0.25, false ], scenario.values_at("total", "spread", "agrees")
    assert_equal [ 1, 2 ], scenario["replays"].map { |replay| replay["attempt"] }
    assert_equal [ "Cited none of the evidence a right answer links to." ], scenario["replays"].last["notes"]
    assert_equal [ 2, 0, 1 ], inertia_props["run"].values_at("repeats", "agreeing", "repeated")
  end

  test "a run lists the scenario that dropped most since the run before on the same model first" do
    as_operator
    finished_run(at: 2.days.ago, totals: { "release" => [ 1.0, 1.0, 1.0, 1.0 ], "flaky" => [ 1.0, 1.0, 1.0, 1.0 ] })
    run = finished_run(at: 1.hour.ago, totals: { "release" => [ 1.0, 1.0, 1.0, 1.0 ], "flaky" => [ 0.0, 0.0, 1.0, 1.0 ] })

    get operator_halon_bench_path(run), headers: inertia_headers

    first = inertia_props["scenarios"].first
    assert_equal [ "flaky", 0.5, 1.0, -0.5 ], [ first["scenario"], first["total"], first["previousTotal"], first["change"] ]
    assert_equal [ "Never called start_watch." ], first["replays"].sole["notes"]
    assert inertia_props["previousId"].present?
  end

  test "two runs compared say which scenarios dropped and whether the total fell by more than the noise" do
    as_operator
    base = finished_run(at: 2.days.ago, totals: { "release" => [ 1.0, 1.0, 1.0, 1.0 ], "flaky" => [ 1.0, 1.0, 1.0, 1.0 ] })
    head = finished_run(at: 1.hour.ago, totals: { "release" => [ 1.0, 1.0, 1.0, 1.0 ], "flaky" => [ 0.0, 0.0, 1.0, 1.0 ] })

    get compare_operator_halon_benches_path(base: base.id, head: head.id), headers: inertia_headers

    comparison = inertia_props["comparison"]
    assert comparison["dropped"]
    assert_equal({ "base" => 1.0, "head" => 0.75 }, comparison["total"])
    assert_equal({ "base" => 1.0, "head" => 0.5 }, comparison["dimensions"]["movedForward"])
    assert_equal [ "flaky", -0.5 ], comparison["rows"].min_by { |row| row["delta"] }.values_at("scenario", "delta")
  end

  private

  RegistryModel = Struct.new(:id, :name, :provider)

  def registry_model(id, name, provider) = RegistryModel.new(id, name, provider)

  def finished_run(at:, totals: {})
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_CI, prompt_version: SecureRandom.hex(6),
                                         model: "gpt-4o", status: Conversation::BenchRun::STATUS_FINISHED, created_at: at, finished_at: at)
    totals.each do |scenario, scores|
      score = Conversation::BenchScore.new(*scores)
      run.results.create!(workspace: @workspace, scenario: scenario, title: scenario.humanize, status: Conversation::BenchResult::STATUS_SCORED,
                          **score.to_h, total: score.total, notes: score.total < 1 ? [ "Never called start_watch." ] : [])
    end
    run
  end

  def as_operator
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end
end
