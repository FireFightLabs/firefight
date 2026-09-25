module Operator
  # Every workflow run, one run's steps and events, and pausing, resuming or cancelling it. What an operator does
  # is recorded on the workflow's own events under their name.
  class WorkflowsController < BaseController
    PER_PAGE = 25

    before_action :set_workflow, only: %i[show pause resume cancel]

    def index
      page = [ params[:page].to_i, 1 ].max
      workflows = WorkflowRuns.recent(state: params[:state], kind: params[:kind]).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/workflows/index", props: {
        workflows: OperatorWorkflowRowSerializer.many(workflows.first(PER_PAGE)),
        page: page, more: workflows.size > PER_PAGE,
        kinds: WorkflowRuns.kinds,
        counts: WorkflowRuns.counts_by_state,
        filter: { state: params[:state].presence, kind: params[:kind].presence }
      }
    end

    def show
      render inertia: "operator/workflows/show", props: {
        workflow: OperatorWorkflowSerializer.one(@workflow)
      }
    end

    # The engine's pause and resume say nothing back, so the state they leave is what says whether they worked.
    def pause
      @workflow.pause!(reason: "Paused from the operator console", by: operator_label)
      respond(@workflow.reload.paused?, "#{@workflow.workflow_class} is paused.", "Only a running workflow can be paused.")
    end

    def resume
      @workflow.resume!(by: operator_label)
      respond(@workflow.reload.running?, "#{@workflow.workflow_class} is running again.", "Only a paused workflow can be resumed.")
    end

    def cancel
      moved = @workflow.cancel!(reason: "Cancelled from the operator console", by: operator_label)
      respond(moved, "#{@workflow.workflow_class} is cancelled.", "This workflow has already finished.")
    end

    private

    def set_workflow
      @workflow = WorkflowRuns.find(params[:id])
    end

    def respond(moved, done, refused)
      redirect_to operator_workflow_path(@workflow), moved ? { notice: done } : { alert: refused }
    end
  end
end
