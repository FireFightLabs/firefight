module Operator
  # Chat bench runs and their scenarios, read from what the app records about each run, and two runs side by side. A
  # run replays each scenario a few times, so a scenario's scores are the mean of its repeats with how far apart they lay.
  class HalonBench
    # A run with how many scenarios it scored and how many replays could not finish or are still going, the mean of each
    # score over its scenarios, how far apart its passes lay and how many scenarios' repeats agree.
    Row = Data.define(:run, :scored, :errored, :pending, :total, :quality, :means, :spread, :agreeing, :repeated, :spent_micros, :judge_spent_micros)
    # A scenario's repeats with its total in the run before on the same model.
    Scenario = Data.define(:tally, :previous_total) do
      def replays = tally.replays

      def change
        (tally.total - previous_total).round(3) if tally.total && previous_total
      end
    end
    # Scored scenarios come first, the one that dropped most since the run before at the top, then those that could not finish.
    STATUS_ORDER = [ Conversation::BenchResult::STATUS_SCORED, Conversation::BenchResult::STATUS_ERRORED, Conversation::BenchResult::STATUS_PENDING ].freeze
    # What the page reads of each replay, in one query for every run on it.
    READ = [ :bench_run_id, :scenario, :title, :attempt, :status, :spent_micros, *Conversation::BenchScore.dimensions ].freeze

    Replay = Data.define(:scenario, :title, :attempt, :status, :spent_micros, :score, :notes)

    # Every run on the page in two queries, one for its replays and one for what the judge's calls cost.
    def self.rows(runs)
      ids = runs.map(&:id)
      replays = Conversation::BenchResult.where(bench_run_id: ids).pluck(*READ).group_by(&:first)
      judged = Inference.where(feature: FirefightAi::ReplayJudge::FEATURE, inferable_type: Conversation::BenchResult.name)
                        .joins("INNER JOIN conversation_bench_results ON conversation_bench_results.id = inferences.inferable_id")
                        .where(conversation_bench_results: { bench_run_id: ids }).group("conversation_bench_results.bench_run_id").sum(:cost_micros)
      runs.map { |run| row(run, (replays[run.id] || []).map { |values| replay(values) }, judged[run.id].to_i) }
    end

    def self.row(run, replays, judge_spent_micros)
      tallies = Conversation::BenchTally.of_results(replays)
      scored = tallies.select(&:scored?)
      Row.new(
        run: run, scored: scored.size, errored: replays.count { |replay| replay.status == Conversation::BenchResult::STATUS_ERRORED },
        pending: replays.count { |replay| replay.status == Conversation::BenchResult::STATUS_PENDING },
        total: mean(scored.map(&:total)), quality: mean(scored.map(&:quality)),
        means: Conversation::BenchScore.dimensions.index_with { |name| mean(scored.map { |tally| tally.score.public_send(name) }) },
        spread: Conversation::BenchTally.spread(tallies), agreeing: Conversation::BenchTally.agreeing(tallies),
        repeated: Conversation::BenchTally.repeated(tallies), spent_micros: replays.sum(&:spent_micros), judge_spent_micros: judge_spent_micros
      )
    end

    def self.replay(values)
      _run, scenario, title, attempt, status, spent_micros, *scores = values
      Replay.new(scenario: scenario, title: title, attempt: attempt, status: status, spent_micros: spent_micros, notes: [],
                 score: Conversation::BenchScore.new(**Conversation::BenchScore.dimensions.zip(scores).to_h))
    end

    def self.scenarios(run)
      before = previous(run)&.then { |earlier| Conversation::BenchTally.of_run(earlier).to_h { |tally| [ tally.scenario, tally.total ] } }
      Conversation::BenchTally.of_results(run.results.to_a).map { |tally| Scenario.new(tally: tally, previous_total: before&.dig(tally.scenario)) }
                              .sort_by.with_index { |entry, index| [ STATUS_ORDER.index(entry.tally.status), entry.change || 0, index ] }
    end

    # The run before this one on the same model, for which scenarios changed between them.
    def self.previous(run)
      Conversation::BenchRun.of_scenarios.where(model: run.model, provider: run.provider).where(created_at: ...run.created_at).recent.first
    end

    def self.compare(base, head) = Conversation::BenchComparison.from_runs(base, head)

    def self.scenario_count = Conversation::BenchCase.scenarios.size

    def self.mean(values)
      given = values.compact
      given.empty? ? nil : (given.sum / given.size).round(3)
    end
  end
end
