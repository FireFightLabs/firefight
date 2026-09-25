module Operator
  # Halon's numbers for a window, how runs ended, how long they took, what they cost, which tools and model calls
  # failed, and how people voted. Rehearsals are excluded.
  class HalonHealth
    Totals = Data.define(:runs, :live, :chat_turns, :answered, :finished, :median_seconds, :p90_seconds, :spent_micros, :median_run_micros)
    Bucket = Data.define(:at, :answered, :stopped, :failed, :live)
    Reason = Data.define(:reason, :ending, :count)
    Tool = Data.define(:action_key, :calls, :errors, :denied, :median_ms)
    Model = Data.define(:calls, :errors, :median_ms, :p90_ms, :error_classes)
    Prompt = Data.define(:version, :first_seen_at, :text, :runs, :answered, :finished, :median_turns, :median_micros, :confirmed, :wrong)

    TOOL_LIMIT = 25
    PROMPT_LIMIT = 5

    # Median and p90 as SQL, each written out in full so no SQL is built from strings.
    RUN_SECONDS = [
      "percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM investigations.completed_at - investigations.started_at))",
      "percentile_cont(0.9) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM investigations.completed_at - investigations.started_at))"
    ].map { |sql| Arel.sql(sql) }.freeze
    RUN_SPEND = [
      "percentile_cont(0.5) WITHIN GROUP (ORDER BY investigations.spent_micros)",
      "percentile_cont(0.9) WITHIN GROUP (ORDER BY investigations.spent_micros)"
    ].map { |sql| Arel.sql(sql) }.freeze
    MODEL_LATENCY = [
      "percentile_cont(0.5) WITHIN GROUP (ORDER BY inferences.latency_ms)",
      "percentile_cont(0.9) WITHIN GROUP (ORDER BY inferences.latency_ms)"
    ].map { |sql| Arel.sql(sql) }.freeze

    def initialize(filter)
      @filter = filter
      @runs = HalonRuns.in(filter)
    end

    def totals
      durations = percentiles(finished_runs.where.not(started_at: nil), RUN_SECONDS)
      Totals.new(
        runs: rows.size, live: rows.count { |row| row[:ending] == HalonRuns::ENDING_LIVE },
        chat_turns: chat_turns, answered: rows.count { |row| row[:ending] == HalonRuns::ENDING_ANSWERED },
        finished: rows.count { |row| row[:ending] != HalonRuns::ENDING_LIVE },
        median_seconds: durations[0]&.round, p90_seconds: durations[1]&.round,
        spent_micros: inferences.sum(:cost_micros), median_run_micros: percentiles(finished_runs, RUN_SPEND)[0]&.round
      )
    end

    def verdicts
      scope = Investigation::Verdict.joins(finding: :investigation).merge(Investigation.seen).where(created_at: @filter.range)
      @filter.scope(scope, "investigations.workspace_id").group(:outcome).count
    end

    def buckets
      by_bucket = rows.group_by { |row| row[:at].utc.public_send(@filter.bucket == :hour ? :beginning_of_hour : :beginning_of_day) }
      @filter.buckets.map do |start|
        endings = (by_bucket[start] || []).map { |row| row[:ending] }.tally
        Bucket.new(at: start, answered: endings.fetch(HalonRuns::ENDING_ANSWERED, 0), stopped: endings.fetch(HalonRuns::ENDING_STOPPED, 0),
                   failed: endings.fetch(HalonRuns::ENDING_FAILED, 0), live: endings.fetch(HalonRuns::ENDING_LIVE, 0))
      end
    end

    # Why runs did not answer, grouped by reason. Failures are grouped by their technical cause.
    def reasons
      rows.select { |row| [ HalonRuns::ENDING_STOPPED, HalonRuns::ENDING_FAILED ].include?(row[:ending]) }
          .group_by { |row| [ row[:ending], reason_for(row) ] }
          .map { |(ending, reason), group| Reason.new(reason:, ending:, count: group.size) }
          .sort_by { |reason| -reason.count }
    end

    def tools
      scope = @filter.scope(Ability::Invocation.where(source: [ AbilityGateway::SOURCE_INVESTIGATION, AbilityGateway::SOURCE_CONVERSATION ], created_at: @filter.range))
      scope.group(:action_key).order(Arel.sql("COUNT(*) DESC")).limit(TOOL_LIMIT).pluck(
        :action_key, Arel.sql("COUNT(*)"),
        Arel.sql(ActiveRecord::Base.sanitize_sql([ "COUNT(*) FILTER (WHERE outcome = ?)", Ability::Invocation::OUTCOME_ERROR ])),
        Arel.sql(ActiveRecord::Base.sanitize_sql([ "COUNT(*) FILTER (WHERE decision = ?)", Ability::Invocation::DECISION_DENY ])),
        Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms)")
      ).map { |action_key, calls, errors, denied, median| Tool.new(action_key:, calls:, errors:, denied:, median_ms: median&.round) }
    end

    def model
      succeeded = inferences.where(status: Inference::STATUS_SUCCESS)
      latency = percentiles(succeeded, MODEL_LATENCY)
      Model.new(
        calls: inferences.count, errors: inferences.where(status: Inference::STATUS_ERROR).count,
        median_ms: latency[0]&.round, p90_ms: latency[1]&.round,
        error_classes: inferences.where(status: Inference::STATUS_ERROR).group(:error_class).count
      )
    end

    # The latest versions of the run prompt, each with results for the runs that used it. Covers all time, so older
    # versions stay available to compare.
    def prompts
      versions = PromptVersion.where(template: FirefightAi::Investigator::FEATURE).order(first_seen_at: :desc).limit(PROMPT_LIMIT)
      ledger = @filter.scope(Inference.where(prompt_template: FirefightAi::Investigator::FEATURE, prompt_version: versions.map(&:version), inferable_type: Investigation.name))
      # A run that spans a deploy counts under the version it started with.
      first_version = ledger.order(:created_at).pluck(:inferable_id, :prompt_version).reverse.to_h
      runs = Investigation.seen.where(id: first_version.keys).includes(:finding).index_by(&:id)

      versions.map do |version|
        drove = first_version.filter_map { |run_id, used| runs[run_id] if used == version.version }
        prompt_row(version, drove)
      end
    end

    private

    def rows
      @rows ||= @runs.pluck(:created_at, :status, :error_summary).map do |at, status, error_summary|
        { at: at, error_summary: error_summary, ending: HalonRuns.ending(status, error_summary) }
      end
    end

    def reason_for(row)
      return Investigation::STOPPED_BY_A_RESPONDER if row[:ending] == HalonRuns::ENDING_STOPPED && row[:error_summary].blank?

      row[:error_summary].presence || "No cause recorded"
    end

    def finished_runs = @runs.where.not(completed_at: nil)

    def inferences
      @filter.scope(Inference.where(feature: HalonRuns::FEATURES, created_at: @filter.range))
    end

    def chat_turns
      scope = Chat::Message.joins(:chat).where(chats: { owner_type: Conversation.name }, role: Chat::Message::ROLE_USER, nudge: false, created_at: @filter.range)
      @filter.scope(scope, "chats.workspace_id").count
    end

    def percentiles(relation, columns) = relation.pick(*columns) || []

    def prompt_row(version, runs)
      finished = runs.select(&:over?)
      outcomes = runs.filter_map { |run| run.finding&.outcome }.tally
      Prompt.new(
        version: version.version, first_seen_at: version.first_seen_at, text: version.text, runs: runs.size,
        answered: finished.count { |run| run.status == Investigation::STATUS_SUCCEEDED }, finished: finished.size,
        median_turns: median(finished.map(&:turns_used)), median_micros: median(finished.map(&:spent_micros)),
        confirmed: outcomes.fetch(Investigation::Finding::OUTCOME_CONFIRMED, 0), wrong: outcomes.fetch(Investigation::Finding::OUTCOME_WRONG, 0)
      )
    end

    def median(values)
      return nil if values.empty?

      sorted = values.sort
      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0).round
    end
  end
end
