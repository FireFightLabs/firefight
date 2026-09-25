module Operator
  # Runs a failed step again, or skips it. Either one sets a failed workflow back to running.
  class WorkflowStepsController < BaseController
    before_action :set_step

    def run_again
      blocked = Actions.step_blocked_reason(@step)
      return refuse(blocked) if blocked

      @step.retry_now!
      done("#{@step.name} will run again now.")
    end

    def skip
      blocked = Actions.step_blocked_reason(@step)
      return refuse(blocked) if blocked

      @step.skip!(reason: "Skipped from the operator console by #{operator_label}")
      done("#{@step.name} is skipped, and the rest of the workflow carries on.")
    end

    private

    def set_step
      @step = WorkflowRuns.find_step(params[:id])
    end

    # Returns to the page the operator acted from, the workflow or the incident timeline.
    def done(message) = redirect_back(fallback_location: operator_workflow_path(@step.workflow), notice: message)

    def refuse(message) = redirect_back(fallback_location: operator_workflow_path(@step.workflow), alert: message)
  end
end
