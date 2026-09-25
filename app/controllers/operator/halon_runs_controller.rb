module Operator
  # One run's trace. A span's content is read only when the operator opens it, since tool output is large and is the
  # customer's data.
  class HalonRunsController < BaseController
    def show
      run = Investigation.includes(:workspace, :subject, :finding, :triggered_by).find(params[:id])
      trace = RunTrace.new(run)

      render inertia: "operator/halon/run", props: {
        run: OperatorHalonRunSerializer.one(run),
        promptVersion: trace.prompt_version,
        model: trace.model,
        groups: OperatorTraceGroupSerializer.many(trace.groups),
        Trace::BODY_PROP => InertiaRails.optional { trace.body_for(params[Trace::SPAN_PARAM].to_s) }
      }
    end
  end
end
