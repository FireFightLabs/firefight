module Operator
  # Lists workflow runs, shows one run with its steps and events, and pauses, resumes or cancels it. Each action is
  # recorded on the workflow with the operator's email.
  class WorkflowsController < BaseController
    PER_PAGE = 25

    before_action :set_workflow, only: %i[show pause resume cancel]

    def index
      page = [ params[:page].to_i, 1 ].max
      workflows = WorkflowRuns.recent(state: params[:state], kind: params[:kind]).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/workflows/index", props: {
        workflows: WorkflowRowSerializer.many(workflows.first(PER_PAGE)),
        page: page, more: workflows.size > PER_PAGE,
        kinds: WorkflowRuns.kinds,
        counts: WorkflowRuns.counts_by_state,
        filter: { state: params[:state].presence, kind: params[:kind].presence }
      }
    end

    def show
      render inertia: "operator/workflows/show", props: {
        workflow: WorkflowSerializer.one(@workflow)
      }
    end

    # The engine's pause! and resume! return nothing useful, so the state after the call shows whether it worked.
    def pause
      blocked = Actions.pause_blocked_reason(@workflow)
      return respond(false, nil, blocked) if blocked

      @workflow.pause!(reason: "Paused from the operator console", by: operator_label)
      respond(@workflow.reload.paused?, "#{@workflow.workflow_class} is paused.", "#{@workflow.workflow_class} could not be paused. It may have just finished.")
    end

    def resume
      blocked = Actions.resume_blocked_reason(@workflow)
      return respond(false, nil, blocked) if blocked

      @workflow.resume!(by: operator_label)
      respond(@workflow.reload.running?, "#{@workflow.workflow_class} is running again.", "#{@workflow.workflow_class} could not be resumed.")
    end

    def cancel
      blocked = Actions.cancel_blocked_reason(@workflow)
      return respond(false, nil, blocked) if blocked

      moved = @workflow.cancel!(reason: "Cancelled from the operator console", by: operator_label)
      respond(moved, "#{@workflow.workflow_class} is cancelled.", "#{@workflow.workflow_class} could not be cancelled. It may have just finished.")
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
