# Replays the latest answers the team rated on a version of Halon, and grades each replay against what the team said.
# A replay answers every call from what the original run read, so only Halon's reasoning is tested and nothing new is
# read from the workspace's systems. Nothing is posted, and none of it becomes a past answer.
class Investigation::Regression
  NO_ANSWER = "The replay ended without an answer.".freeze
  OPTED_OUT = "The workspace stopped letting Firefight test Halon before this case was replayed.".freeze
  LOST = "The replay stopped without finishing, so its worker was lost.".freeze

  class << self
    # Runs once for each version of Halon's prompt as it is deployed. Nil when this version already had its run, or
    # no workspace has a rated answer to test it on yet, so the next check tries again.
    def start_for_prompt_change!
      return unless defined?(FirefightAi)
      return if Investigation::RegressionRun.exists?(trigger: Investigation::RegressionRun::TRIGGER_PROMPT_CHANGE, prompt_version: prompt_version)

      start!(trigger: Investigation::RegressionRun::TRIGGER_PROMPT_CHANGE)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Nil when there is nothing to test. model and provider name another model to try, nil means Halon's own.
    def start!(trigger:, model: nil, provider: nil, by: nil)
      cases = Investigation::Finding.regression_cases.limit(Investigation::RegressionRun::CASES).to_a
      return if cases.empty?

      run = Investigation::RegressionRun.transaction do
        Investigation::RegressionRun.create!(
          trigger: trigger, prompt_version: prompt_version, model: model.presence, provider: provider.presence, started_by: by
        ).tap { |created| cases.each { |finding| created.results.create!(finding: finding, expected: finding.outcome) } }
      end
      run.results.each { |result| HalonRegressionCaseJob.perform_later(result.id) }
      run
    end

    def run_case!(result)
      return unless result.claim!
      return result.settle!(status: Investigation::RegressionResult::STATUS_SKIPPED, reason: OPTED_OUT) unless replayable?(result.finding.investigation.workspace)

      grade(result)
    rescue StandardError => error
      Rails.logger.warn({ event: "halon_regression.case_errored", result_id: result.id, error: error.class.name }.to_json)
      result.settle!(status: Investigation::RegressionResult::STATUS_ERRORED, reason: "The replay could not finish (#{error.class.name}).",
                     spent_micros: result.replay&.reload&.spent_micros.to_i)
    ensure
      result.regression_run.finish_if_done!
    end

    # A case whose worker died is settled, so its run can finish.
    def settle_stale!
      Investigation::RegressionResult.stale.includes(:regression_run, :replay).find_each do |result|
        result.settle!(status: Investigation::RegressionResult::STATUS_ERRORED, reason: LOST, spent_micros: result.replay&.spent_micros.to_i)
        result.regression_run.finish_if_done!
      end
    end

    def prompt_version = FirefightAi::Investigator.prompt_version

    private

    def grade(result)
      run = result.regression_run
      replayed = Investigation::Rehearsal.replay!(result.finding.investigation, model: run.model, provider: run.provider,
                                                  started: ->(replay) { result.update_columns(replay_id: replay.id) })
      replay = replayed.investigation
      return result.settle!(status: Investigation::RegressionResult::STATUS_FAILED, reason: NO_ANSWER, spent_micros: replay.spent_micros) if replayed.summary.blank?

      answer = said(replayed.summary, replayed.cause)
      verdict = FirefightAi::AnswerJudge.new(replay.workspace, inferable: replay).judge(rated: said(result.finding.summary, result.finding.winning_hypothesis&.assertion), replayed: answer)
      result.settle!(status: passed?(result.expected, verdict.verdict) ? Investigation::RegressionResult::STATUS_PASSED : Investigation::RegressionResult::STATUS_FAILED,
                     answer: answer, reason: verdict.reason, spent_micros: replay.spent_micros)
    end

    # A confirmed answer has to be reached again. A wrong one has to be avoided, and a replay that names no cause has
    # neither repeated it nor answered, so it does not pass.
    def passed?(expected, verdict)
      return verdict == FirefightAi::Schemas::SameCause::SAME if expected == Investigation::Finding::OUTCOME_CONFIRMED

      verdict == FirefightAi::Schemas::SameCause::DIFFERENT
    end

    # Checked again as each case starts, so turning the setting off stops what is still queued.
    def replayable?(workspace)
      workspace.halon_regression_enabled && Entitlements.allows?(workspace, Entitlements::AI)
    end

    def said(summary, cause) = [ summary, ("The cause given: #{cause}" if cause.present?) ].compact.join("\n")
  end
end
