# A member's request to publish a workflow, answered from the Workflows page or the canvas: Publish makes the draft
# live and grants the workflow's own identity what it needs, and Dismiss leaves it a draft. Either way the member is told.
class WorkflowPublishRequestsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKFLOWS, update: %i[publish dismiss]

  before_action :set_request

  def publish
    workflow = @request.workflow
    draft = workflow.draft
    return redirect_back(fallback_location: halon_workflows_path, alert: "#{workflow.name} has no draft to publish any more.") unless draft
    return unless workflow.missing_reach(draft).empty? || authorize_web!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)

    result = WorkflowPublishService.new(workflow).publish_requested!(@request, by: current_membership)
    redirect_back fallback_location: halon_workflows_path, (result.ok ? :notice : :alert) => result.words
  end

  def dismiss
    result = WorkflowPublishService.new(@request.workflow).dismiss!(@request, by: current_membership)
    redirect_back fallback_location: halon_workflows_path, (result.ok ? :notice : :alert) => result.words
  end

  private

  def set_request
    @request = Workflow::PublishRequest.where(workspace: current_workspace).includes(:workflow, :requester).find(params[:id])
  end
end
