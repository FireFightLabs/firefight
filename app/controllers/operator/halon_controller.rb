module Operator
  # How Halon is doing in a window, and its runs, each of which opens its trace.
  class HalonController < BaseController
    PER_PAGE = 25

    def show
      health = HalonHealth.new(filter)
      ending = params[:ending].presence_in(HalonRuns::ENDINGS)
      page = [ params[:page].to_i, 1 ].max
      runs = HalonRuns.list(filter, ending: ending).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/halon/show", props: {
        totals: camelized(health.totals),
        verdicts: health.verdicts,
        buckets: health.buckets.map { |bucket| camelized(bucket) },
        reasons: health.reasons.map { |reason| camelized(reason) },
        tools: health.tools.map { |tool| camelized(tool) },
        model: camelized(health.model),
        prompts: health.prompts.map { |prompt| camelized(prompt) },
        runs: OperatorHalonRunSerializer.many(runs.first(PER_PAGE)),
        page: page, more: runs.size > PER_PAGE, ending: ending,
        **filter_props
      }
    end
  end
end
