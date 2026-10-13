# One run of a workflow: what it did step by step, pinned to keep its details past the workspace's retention, or stopped
# while it still goes.
class WorkflowRunsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: %i[show], update: %i[pin unpin cancel]

  include RequiresWorkflows

  before_action :set_run

  def show
    render inertia: "halon/workflow-run", props: { run: WorkflowRunSerializer.one(@run) }
  end

  def pin
    @run.pin!(true)
    redirect_to workflow_run_path(@run.workflow, @run), notice: "This run is pinned, so it keeps its details."
  rescue Workflow::Run::Refused => refused
    redirect_to workflow_run_path(@run.workflow, @run), alert: refused.message
  end

  def unpin
    @run.pin!(false)
    redirect_to workflow_run_path(@run.workflow, @run), notice: "This run is no longer pinned."
  end

  def cancel
    @run.cancel!(by: current_membership)
    redirect_to workflow_run_path(@run.workflow, @run), notice: "The run of #{@run.workflow.name} was stopped."
  rescue Workflow::Run::Refused => refused
    redirect_to workflow_run_path(@run.workflow, @run), alert: refused.message
  end

  private

  def set_run
    workflow = current_workspace.workflows.find(params[:workflow_id])
    @run = workflow.runs.includes(:workflow, :version, :started_by, :agent, :steps).find(params[:id])
  end
end
