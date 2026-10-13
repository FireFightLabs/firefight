# One result a run's step kept whole because it was too large to carry, read from the run's view when someone opens it.
class WorkflowSavedResultsController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: :show

  def show
    result = workflow.runs.find(params[:run_id]).saved_results.find(params[:result_id])
    render json: { name: result.tool_name, text: result.content }
  end
end
