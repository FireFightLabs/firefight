module Operator
  # Chat bench runs and their scenarios, read from what the app records about each run, and two runs side by side.
  class HalonBench
    # A run with how many scenarios it scored and the mean of each score over them.
    Row = Data.define(:run, :scored, :errored, :pending, :total, :means, :spent_micros)
    # A scenario with its total in the run before on the same model.
    Scenario = Data.define(:result, :previous_total) do
      def change
        (result.total - previous_total).round(3) if result.total && previous_total
      end
    end
    # Scored scenarios come first, the one that dropped most since the run before at the top, then those that could not finish.
    STATUS_ORDER = [ Conversation::BenchResult::STATUS_SCORED, Conversation::BenchResult::STATUS_ERRORED, Conversation::BenchResult::STATUS_PENDING ].freeze

    # Counts, means and spend for every run on the page in three queries.
    def self.rows(runs)
      ids = runs.map(&:id)
      counts = Conversation::BenchResult.where(bench_run_id: ids).group(:bench_run_id, :status).count
      dimensions = [ :total, *Conversation::BenchScore.dimensions ]
      table = Conversation::BenchResult.arel_table
      means = Conversation::BenchResult.scored.where(bench_run_id: ids).group(:bench_run_id)
                                       .pluck(:bench_run_id, *dimensions.map { |name| table[name].average }).to_h { |id, *values| [ id, values ] }
      spent = Conversation::BenchResult.where(bench_run_id: ids).group(:bench_run_id).sum(:spent_micros)
      runs.map do |run|
        averages = means[run.id] || Array.new(dimensions.size)
        rounded = dimensions.zip(averages).to_h { |name, value| [ name, value&.round(3) ] }
        Row.new(run: run, scored: counts[[ run.id, Conversation::BenchResult::STATUS_SCORED ]].to_i,
                errored: counts[[ run.id, Conversation::BenchResult::STATUS_ERRORED ]].to_i, pending: counts[[ run.id, Conversation::BenchResult::STATUS_PENDING ]].to_i,
                total: rounded.delete(:total), means: rounded, spent_micros: spent[run.id].to_i)
      end
    end

    def self.scenarios(run)
      before = previous(run)&.results&.scored&.pluck(:scenario, :total).to_h
      run.results.order(:scenario).map { |result| Scenario.new(result: result, previous_total: before&.dig(result.scenario)) }
         .sort_by.with_index { |entry, index| [ STATUS_ORDER.index(entry.result.status), entry.change || 0, index ] }
    end

    # The run before this one on the same model, for which scenarios changed between them.
    def self.previous(run)
      Conversation::BenchRun.of_scenarios.where(model: run.model, provider: run.provider).where(created_at: ...run.created_at).recent.first
    end

    def self.compare(base, head) = Conversation::BenchComparison.from_runs(base, head)

    def self.scenario_count = Conversation::BenchCase.scenarios.size
  end
end
