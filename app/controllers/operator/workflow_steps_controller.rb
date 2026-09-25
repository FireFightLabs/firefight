module Operator
  # Running a failed step again, or going on without it. Either brings a failed workflow back to running.
  class WorkflowStepsController < BaseController
    before_action :set_step

    def run_again
      return refuse("Only a failed step can be run again.") unless @step.failed?

      @step.retry_now!
      done("#{@step.name} will run again now.")
    end

    def skip
      return refuse("Only a failed step can be skipped.") unless @step.failed?

      @step.skip!(reason: "Skipped from the operator console by #{operator_label}")
      done("#{@step.name} is skipped, and the rest of the workflow carries on.")
    end

    private

    def set_step
      @step = WorkflowRuns.find_step(params[:id])
    end

    # Back to where the operator pressed it, the workflow or the incident's timeline.
    def done(message) = redirect_back(fallback_location: operator_workflow_path(@step.workflow), notice: message)

    def refuse(message) = redirect_back(fallback_location: operator_workflow_path(@step.workflow), alert: message)
  end
end
