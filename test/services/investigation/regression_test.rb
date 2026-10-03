require "test_helper"

class Investigation::RegressionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(halon_regression_enabled: true)
    @confirmed = rated("The disk on db-1 filled", Investigation::Finding::OUTCOME_CONFIRMED)
    @wrong = rated("The deploy at 14:02 did it", Investigation::Finding::OUTCOME_WRONG)
  end

  test "a run takes only rated answers from workspaces that opted in, never a rehearsal or an unrated one" do
    rated("A rehearsal's answer", Investigation::Finding::OUTCOME_CONFIRMED, rehearsal: true)
    rated("Nobody rated this", nil)
    other = workspaces(:slack_workspace_two)
    rated("Not opted in", Investigation::Finding::OUTCOME_CONFIRMED, workspace: other)

    run = nil
    assert_enqueued_jobs(2, only: HalonRegressionCaseJob) { run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR) }

    assert_equal [ @confirmed.id, @wrong.id ].sort, run.results.map(&:finding_id).sort
    assert_equal FirefightAi::Investigator.prompt_version, run.prompt_version
    assert_equal({ @confirmed.id => "confirmed", @wrong.id => "wrong" }, run.results.to_h { |result| [ result.finding_id, result.expected ] })
  end

  test "a deployed prompt is tested once, and nothing is started while there is nothing to test" do
    first = Investigation::Regression.start_for_prompt_change!

    assert_equal Investigation::RegressionRun::TRIGGER_PROMPT_CHANGE, first.trigger
    assert_nil Investigation::Regression.start_for_prompt_change!

    @workspace.update!(halon_regression_enabled: false)
    Investigation::RegressionRun.delete_all
    assert_nil Investigation::Regression.start_for_prompt_change!
    assert_not Investigation::RegressionRun.exists?
  end

  test "a confirmed answer passes when the replay names the same cause, a wrong one only when it does not repeat it" do
    run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR)
    replay_answers("The disk on db-1 filled up")
    judge(FirefightAi::Schemas::SameCause::SAME, "Both blame the full disk on db-1.")

    run.results.each { |result| Investigation::Regression.run_case!(result) }

    statuses = run.results.reload.to_h { |result| [ result.finding_id, result.status ] }
    assert_equal Investigation::RegressionResult::STATUS_PASSED, statuses[@confirmed.id]
    assert_equal Investigation::RegressionResult::STATUS_FAILED, statuses[@wrong.id], "repeating an answer the team marked wrong fails"
    assert_equal "Both blame the full disk on db-1.", run.results.find_by!(finding: @confirmed).reason
    assert_equal Investigation::RegressionRun::STATUS_FINISHED, run.reload.status
  end

  test "a replay that breaks could not finish, the run still ends, and a retried case never overwrites its grade" do
    run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR)
    Investigation::Rehearsal.stubs(:replay!).raises(FirefightAi::TerminalError, "nope")

    run.results.each { |result| Investigation::Regression.run_case!(result) }

    assert_equal [ Investigation::RegressionResult::STATUS_ERRORED ], run.results.reload.map(&:status).uniq
    assert_equal Investigation::RegressionRun::STATUS_FINISHED, run.reload.status

    Investigation::Rehearsal.expects(:replay!).never
    Investigation::Regression.run_case!(run.results.first)
  end

  test "a replay with no answer fails rather than being graded" do
    run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR)
    replay_answers(nil)
    FirefightAi::AnswerJudge.any_instance.expects(:judge).never

    Investigation::Regression.run_case!(run.results.find_by!(finding: @confirmed))

    result = run.results.find_by!(finding: @confirmed)
    assert_equal [ Investigation::RegressionResult::STATUS_FAILED, Investigation::Regression::NO_ANSWER ], [ result.status, result.reason ]
    assert_equal Investigation::RegressionRun::STATUS_RUNNING, run.reload.status, "the other case is still replaying"
  end

  test "a workspace that opts out mid run has its queued cases skipped, never replayed" do
    run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR)
    @workspace.update!(halon_regression_enabled: false)
    Investigation::Rehearsal.expects(:replay!).never

    run.results.each { |result| Investigation::Regression.run_case!(result) }

    assert_equal [ Investigation::RegressionResult::STATUS_SKIPPED ], run.results.reload.map(&:status).uniq
    assert_equal Investigation::RegressionRun::STATUS_FINISHED, run.reload.status
  end

  test "a grader that breaks after the replay keeps the replay and what it spent" do
    run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR)
    replay_answers("The disk filled")
    FirefightAi::AnswerJudge.any_instance.stubs(:judge).raises(FirefightAi::TransientError, "busy")
    result = run.results.find_by!(finding: @confirmed)
    Investigation::Rehearsal.stubs(:replay!).with { |*, started:, **| started.call(@replay) || true }.returns(@replayed)

    Investigation::Regression.run_case!(result)

    result.reload
    assert_equal [ Investigation::RegressionResult::STATUS_ERRORED, @replay.id, 120_000 ], [ result.status, result.replay_id, result.spent_micros ]
  end

  test "a case is replayed once however often its job runs, and one whose worker was lost is settled by the hourly check" do
    run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR)
    result = run.results.find_by!(finding: @confirmed)
    result.claim!
    Investigation::Rehearsal.expects(:replay!).never

    Investigation::Regression.run_case!(result)
    assert_equal Investigation::RegressionResult::STATUS_PENDING, result.reload.status

    result.update_columns(started_at: 3.hours.ago)
    HalonRegressionWatchJob.perform_now
    assert_equal [ Investigation::RegressionResult::STATUS_ERRORED, Investigation::Regression::LOST ], [ result.reload.status, result.reason ]
  end

  test "two workers noticing the same deployed prompt start one run" do
    Investigation::RegressionRun.create!(trigger: Investigation::RegressionRun::TRIGGER_PROMPT_CHANGE, prompt_version: Investigation::Regression.prompt_version)
    Investigation::RegressionRun.stubs(:exists?).returns(false)

    assert_nil Investigation::Regression.start_for_prompt_change!
    assert_equal 1, Investigation::RegressionRun.where(prompt_version: Investigation::Regression.prompt_version).count
  end

  private

  def rated(summary, outcome, rehearsal: false, workspace: @workspace)
    incident = workspace.incidents.first
    run = workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                           status: Investigation::STATUS_SUCCEEDED, rehearsal: rehearsal)
    run.create_finding!(summary: summary, outcome: outcome, outcome_at: (Time.current if outcome))
  end

  def replay_answers(summary)
    @replay = replay = @workspace.investigations.create!(subject: @confirmed.investigation.subject, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
                                               max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED, spent_micros: 120_000)
    @replayed = Investigation::Rehearsal::Result.new(
      investigation: replay, model: "m", status: replay.status, summary: summary, cause: nil, claims: [], turns: 3, spent_cents: 12, steps: 4,
      not_recorded: 0, seconds: 30
    )
    Investigation::Rehearsal.stubs(:replay!).returns(@replayed)
  end

  def judge(verdict, reason)
    FirefightAi::AnswerJudge.any_instance.stubs(:judge).returns(FirefightAi::AnswerJudge::Verdict.new(verdict: verdict, reason: reason))
  end
end
