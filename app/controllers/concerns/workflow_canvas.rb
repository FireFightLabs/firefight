# A workflow's canvas and every change made on it, which exist only for a workspace with the workflows flag
# (RequiresWorkflows). Every change made on the canvas goes back to it.
module WorkflowCanvas
  extend ActiveSupport::Concern

  included do
    include RequiresWorkflows
  end

  private

  def workflow
    @workflow ||= Workflow.where(workspace: current_workspace).find(params[:id])
  end

  def back_to_canvas(**flash) = redirect_to(workflow_path(workflow), **flash)
end
