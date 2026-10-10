module Operator
  # The chat bench: Halon replayed on scenarios written from real failures, scored on four things, and two runs compared.
  class HalonBenchesController < BaseController
    PER_PAGE = 25

    def index
      page = [ params[:page].to_i, 1 ].max
      runs = Conversation::BenchRun.of_scenarios.recent.includes(:started_by).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/halon/bench", props: {
        runs: HalonBenchRunSerializer.many(HalonBench.rows(runs.first(PER_PAGE))),
        scenarioCount: HalonBench.scenario_count,
        tolerance: Conversation::BenchComparison::TOLERANCE,
        runBlockedReason: Actions.bench_blocked_reason,
        HalonRegression::MODELS_PROP => InertiaRails.optional { HalonRegressionModelSerializer.many(HalonRegression.models) },
        page: page, more: runs.size > PER_PAGE
      }
    end

    def show
      run = Conversation::BenchRun.of_scenarios.includes(:started_by).find(params[:id])

      render inertia: "operator/halon/bench-run", props: {
        run: HalonBenchRunSerializer.one(HalonBench.rows([ run ]).sole),
        previousId: HalonBench.previous(run)&.id,
        tolerance: Conversation::BenchComparison::TOLERANCE,
        scenarios: HalonBenchScenarioSerializer.many(HalonBench.scenarios(run))
      }
    end

    # Two runs side by side, base the one compared against and head the one it is compared with.
    def compare
      scope = Conversation::BenchRun.of_scenarios.includes(:started_by)
      base = scope.find(params.require(:base))
      head = scope.find(params.require(:head))

      render inertia: "operator/halon/bench-compare", props: {
        base: HalonBenchRunSerializer.one(HalonBench.rows([ base ]).sole),
        head: HalonBenchRunSerializer.one(HalonBench.rows([ head ]).sole),
        comparison: HalonBenchComparisonSerializer.one(HalonBench.compare(base, head))
      }
    end

    def create
      blocked = Actions.bench_blocked_reason
      return redirect_to(operator_halon_benches_path, alert: blocked) if blocked

      chosen = params[:model].presence && HalonRegression.model(params[:model], params[:provider])
      return redirect_to(operator_halon_benches_path, alert: "That model is not one Firefight can price, so choose another.") if params[:model].present? && !chosen

      run = begin
        Conversation::Bench.start!(trigger: Conversation::BenchRun::TRIGGER_OPERATOR, model: chosen&.id, provider: chosen&.provider, by: current_user)
      rescue Conversation::BenchKeys::Missing, Conversation::Bench::Busy => refused
        return redirect_to(operator_halon_benches_path, alert: refused.message)
      end
      redirect_to operator_halon_bench_path(run), notice: "Replaying #{helpers.pluralize(run.results.size, 'scenario')} on #{chosen&.name || "Halon's model"}."
    end
  end
end
