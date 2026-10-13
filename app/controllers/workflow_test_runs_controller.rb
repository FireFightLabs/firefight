# Trying a workflow from the canvas: a test run of the draft with sample inputs and a sample trigger, the whole of it or
# one step with only the steps before it, as the person testing, with every change shown rather than made except on the
# steps they turned on.
class WorkflowTestRunsController < InertiaController
  include WorkflowCanvas
  include FreeFormParams

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: :create

  def create
    run = WorkflowRunService.new(workflow).start!(
      started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: current_membership, test: true,
      inputs: object_param(params[:inputs]) || {}, trigger_payload: object_param(params[:trigger_payload]) || {},
      up_to: params[:up_to].presence, real_step_keys: Array(params[:real_step_keys]).map(&:to_s)
    )
    redirect_to workflow_path(workflow, WorkflowCanvasController::RUN_QUERY_PARAM => run.id), notice: started_words(run)
  rescue Workflow::Run::Refused, Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  private

  def started_words(run)
    return "#{workflow.name} is being tried up to #{Workflow::Edit.title_of(step_name(run, params[:up_to]))}." if params[:up_to].present?

    "#{workflow.name} is being tried."
  end

  def step_name(run, step_id) = Workflow::Version.all_steps(run.ran_snapshot["steps"]).find { |step| step["id"] == step_id }&.dig("name")
end
