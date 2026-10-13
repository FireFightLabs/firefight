# One run of a workflow, which is read on the workflow's canvas (?run=): its own address opens it there. From that view a
# run starts again from a step, a failed step is tried again or a step skipped, the run is stopped while it goes, or its
# details are pinned past the workspace's retention. Each is refused with the model's sentence when it cannot be done.
class WorkflowRunsController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: %i[show], create: %i[rerun retry_step skip_step], update: %i[pin unpin cancel]

  # Links to a run, from Slack, a chat card or the Workflows page, open it on the canvas.
  def show
    redirect_to workflow_path(workflow, WorkflowCanvasController::RUN_QUERY_PARAM => run.id)
  end

  def rerun
    again = WorkflowRunService.rerun_from!(run, step_key: params.require(:step_key), by: current_membership)
    redirect_to workflow_path(workflow, WorkflowCanvasController::RUN_QUERY_PARAM => again.id),
                notice: "#{workflow.name} started again from #{step_title(again.rerun_from_step_key)}."
  rescue Workflow::Run::Refused => error
    back_to_run(alert: error.message)
  end

  def retry_step
    row = run_step
    blocked = row.retry_blocked_reason
    return back_to_run(alert: blocked) if blocked

    DefinedWorkflow.retry_step!(run, row.step_key, row.iteration)
    back_to_run(notice: "#{step_title(row.step_key)} is being tried again.")
  rescue Workflow::Run::Refused => error
    back_to_run(alert: error.message)
  end

  def skip_step
    row = run_step
    blocked = row.skip_blocked_reason
    return back_to_run(alert: blocked) if blocked

    DefinedWorkflow.skip_step!(run, row.step_key, row.iteration, by: current_membership)
    back_to_run(notice: "#{step_title(row.step_key)} was skipped, and the rest of the run carries on.")
  rescue Workflow::Run::Refused => error
    back_to_run(alert: error.message)
  end

  def pin
    run.pin!(true)
    back_to_run(notice: "This run is pinned, so it keeps its details.")
  rescue Workflow::Run::Refused => error
    back_to_run(alert: error.message)
  end

  def unpin
    run.pin!(false)
    back_to_run(notice: "This run is no longer pinned.")
  end

  def cancel
    run.cancel!(by: current_membership)
    back_to_run(notice: "The run of #{workflow.name} was stopped.")
  rescue Workflow::Run::Refused => error
    back_to_run(alert: error.message)
  end

  private

  def workflow
    @workflow ||= Workflow.where(workspace: current_workspace).find(params[:workflow_id] || params[:id])
  end

  def run = @run ||= workflow.runs.find(params[:run_id] || params[:id])

  def run_step = run.steps.find_by!(step_key: params[:step_key], iteration: params[:iteration].to_s)

  def step_title(step_key)
    name = Workflow::Version.all_steps(run.ran_snapshot["steps"]).find { |step| step["id"] == step_key }&.dig("name")
    Workflow::Edit.title_of(name || step_key)
  end

  def back_to_run(**flash) = redirect_to(workflow_path(workflow, WorkflowCanvasController::RUN_QUERY_PARAM => run.id), **flash)
end
