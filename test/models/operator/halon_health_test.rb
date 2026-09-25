require "test_helper"

class Operator::HalonHealthTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @filter = Operator::Filter.new(workspace: @workspace)
  end

  test "a run ends answered, stopped by a limit or a person, or failed on our side" do
    assert_equal Operator::HalonRuns::ENDING_ANSWERED, Operator::HalonRuns.ending(Investigation::STATUS_SUCCEEDED, nil)
    assert_equal Operator::HalonRuns::ENDING_STOPPED, Operator::HalonRuns.ending(Investigation::STATUS_FAILED, Investigation::BUDGET_SPENT)
    assert_equal Operator::HalonRuns::ENDING_STOPPED, Operator::HalonRuns.ending(Investigation::STATUS_CANCELED, Investigation::STOPPED_BY_A_RESPONDER)
    assert_equal Operator::HalonRuns::ENDING_FAILED, Operator::HalonRuns.ending(Investigation::STATUS_FAILED, "RubyLLM::OverloadedError")
    assert_equal Operator::HalonRuns::ENDING_FAILED, Operator::HalonRuns.ending(Investigation::STATUS_FAILED, Investigation::GAVE_UP)
    assert_equal Operator::HalonRuns::ENDING_LIVE, Operator::HalonRuns.ending(Investigation::STATUS_RUNNING, nil)
  end

  test "the list filters by how runs ended, the way each row names it" do
    budget = run!(status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT)
    ours = run!(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")

    stopped = Operator::HalonRuns.list(@filter, ending: Operator::HalonRuns::ENDING_STOPPED).to_a
    failed = Operator::HalonRuns.list(@filter, ending: Operator::HalonRuns::ENDING_FAILED).to_a

    assert_includes stopped, budget
    assert_not_includes stopped, ours
    assert_includes failed, ours
    assert_not_includes failed, budget
  end

  test "totals count runs in the window, how many answered, and what was spent, never a rehearsal" do
    before = Operator::HalonHealth.new(@filter).totals
    run!(status: Investigation::STATUS_SUCCEEDED, started_at: 90.seconds.ago, completed_at: Time.current, spent_micros: 1_320_000)
    run!(status: Investigation::STATUS_FAILED, error_summary: Investigation::TOO_MANY_TURNS)
    run!(status: Investigation::STATUS_SUCCEEDED, rehearsal: true)
    Inference.create!(workspace: @workspace, feature: FirefightAi::Investigator::FEATURE, provider: "anthropic", model: "claude",
                      status: Inference::STATUS_SUCCESS, cost_micros: 60_000)

    totals = Operator::HalonHealth.new(@filter).totals

    assert_equal before.runs + 2, totals.runs
    assert_equal before.answered + 1, totals.answered
    assert_equal before.spent_micros + 60_000, totals.spent_micros
  end

  test "why runs did not answer is counted by reason, a failure by its technical cause" do
    2.times { run!(status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT) }
    run!(status: Investigation::STATUS_FAILED, error_summary: "RubyLLM::OverloadedError")

    reasons = Operator::HalonHealth.new(@filter).reasons

    assert_equal 2, reasons.find { |reason| reason.reason == Investigation::BUDGET_SPENT }.count
    overloaded = reasons.find { |reason| reason.reason == "RubyLLM::OverloadedError" }
    assert_equal Operator::HalonRuns::ENDING_FAILED, overloaded.ending
  end

  test "tools are counted from the ledger with how often they failed or were refused" do
    invocation!("postgresql.run_query", outcome: Ability::Invocation::OUTCOME_ERROR, duration_ms: 600)
    invocation!("postgresql.run_query", outcome: Ability::Invocation::OUTCOME_SUCCESS, duration_ms: 400)
    invocation!("datadog.search_logs", decision: Ability::Invocation::DECISION_DENY)

    tools = Operator::HalonHealth.new(@filter).tools.index_by(&:action_key)

    assert_equal 2, tools["postgresql.run_query"].calls
    assert_equal 1, tools["postgresql.run_query"].errors
    assert_equal 500, tools["postgresql.run_query"].median_ms
    assert_equal 1, tools["datadog.search_logs"].denied
  end

  test "each run prompt wording is compared by the runs it started" do
    PromptVersion.create!(template: FirefightAi::Investigator::FEATURE, version: "aaaaaaaaaaaa", text: "Old wording", first_seen_at: 2.days.ago)
    PromptVersion.create!(template: FirefightAi::Investigator::FEATURE, version: "bbbbbbbbbbbb", text: "New wording", first_seen_at: 1.hour.ago)
    old_run = run!(status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT, turns_used: 12)
    new_run = run!(status: Investigation::STATUS_SUCCEEDED, turns_used: 4)
    ledger!(old_run, "aaaaaaaaaaaa")
    ledger!(new_run, "bbbbbbbbbbbb")

    prompts = Operator::HalonHealth.new(@filter).prompts.index_by(&:version)

    assert_equal 1, prompts["bbbbbbbbbbbb"].answered
    assert_equal 4, prompts["bbbbbbbbbbbb"].median_turns
    assert_equal 0, prompts["aaaaaaaaaaaa"].answered
    assert_equal "Old wording", prompts["aaaaaaaaaaaa"].text
  end

  test "a prompt version is kept as written, so a ledger row finds its wording" do
    inference = Inference.create!(workspace: @workspace, feature: FirefightAi::Investigator::FEATURE, provider: "anthropic",
                                  model: "claude", status: Inference::STATUS_SUCCESS, prompt_version: "683e92b9f7ac")

    assert_equal "683e92b9f7ac", inference.reload.prompt_version
  end

  private

  def run!(status:, rehearsal: false, **attributes)
    @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400, status: status, rehearsal: rehearsal,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" },
      completed_at: (Time.current unless Investigation::LIVE_STATUSES.include?(status)), **attributes
    )
  end

  def invocation!(action_key, decision: Ability::Invocation::DECISION_ALLOW, outcome: nil, duration_ms: nil)
    Ability::Invocation.create!(
      workspace: @workspace, principal: SystemAgent.investigator, principal_label: "Firefight Investigator", action_key: action_key,
      idempotency_key: SecureRandom.uuid, decision: decision, outcome: outcome, duration_ms: duration_ms, source: AbilityGateway::SOURCE_INVESTIGATION
    )
  end

  def ledger!(run, version)
    Inference.create!(workspace: @workspace, feature: FirefightAi::Investigator::FEATURE, provider: "anthropic", model: "claude",
                      status: Inference::STATUS_SUCCESS, inferable: run, prompt_template: FirefightAi::Investigator::FEATURE, prompt_version: version)
  end
end
