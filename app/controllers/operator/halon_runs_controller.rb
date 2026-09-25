module Operator
  # Shows one run as a trace. A span's content loads only when the operator opens it, because tool output can be large
  # and is customer data.
  class HalonRunsController < BaseController
    def show
      run = Investigation.includes(:workspace, :subject, :finding, :triggered_by).find(params[:id])
      trace = RunTrace.new(run)

      render inertia: "operator/halon/run", props: {
        run: HalonRunSerializer.one(run),
        promptVersion: trace.prompt_version,
        model: trace.model,
        groups: TraceGroupSerializer.many(trace.groups),
        Trace::BODY_PROP => InertiaRails.optional { trace.body_for(params[Trace::SPAN_PARAM].to_s) }
      }
    end
  end
end
