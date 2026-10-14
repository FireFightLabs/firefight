# A workflow's settings, changed as its Settings page changes them (Workflow::Settings), by its id or slug. Only what is
# sent changes. Without the workflows flag a workflow answers as one that does not exist.
class Api::V1::WorkflowsController < Api::V1::ApiController
  before_action :require_workflows
  before_action :set_workflow

  def update
    authorize!(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE)

    @workflow.update_settings!(params.permit(*Workflow::Settings::KEYS).to_h)
    render :show
  end

  private

  def set_workflow
    workflows = Workflow.where(workspace: current_workspace)
    @workflow = workflows.find_by(id: params[:id]) || workflows.find_by!(slug: params[:id])
  end

  def require_workflows
    not_found(nil) unless FeatureFlags.enabled?(current_workspace, FeatureFlags::WORKFLOWS)
  end
end
