# A step's output pinned on the draft, taken from a run or written by hand, so test runs try the steps after it without
# calling it again, and unpinned.
class WorkflowPinsController < InertiaController
  include WorkflowCanvas
  include FreeFormParams

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: %i[create destroy]

  def create
    step_id = params.require(:step_id).to_s
    source = params[:run_id].present? ? workflow.runs.find(params[:run_id]) : nil
    output, route = source ? output_from(source, step_id) : [ object_param(params[:output]), params[:route].presence ]
    draft.pin!(step_id: step_id, output: output, route: route, by: current_membership, from_run: source)
    redirect_back_or_to workflow_path(workflow), notice: "#{step_title(step_id)}'s output is pinned."
  rescue Workflow::Edit::Refused => error
    redirect_back_or_to workflow_path(workflow), alert: error.message
  end

  def destroy
    draft.unpin!(params[:step_id].to_s)
    redirect_back_or_to workflow_path(workflow), notice: "#{step_title(params[:step_id])}'s output is no longer pinned."
  rescue Workflow::Edit::Refused => error
    redirect_back_or_to workflow_path(workflow), alert: error.message
  end

  private

  def draft = workflow.draft || raise(Workflow::Edit::Refused, "Only a draft's steps are pinned, so change something first to open one.")

  def output_from(run, step_id)
    row = run.steps.find_by(step_key: step_id, iteration: "")
    raise Workflow::Edit::Refused, "That step gave nothing in this run to pin." unless row&.output.is_a?(Hash)

    [ row.output, row.route ]
  end

  def step_title(step_id) = Workflow::Edit.title_of(workflow.draft&.steps_by_id&.dig(step_id.to_s, "name") || step_id)
end
