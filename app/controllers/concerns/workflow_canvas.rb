# A workflow's canvas and every change made on it. Every change made on the canvas goes back to it.
module WorkflowCanvas
  extend ActiveSupport::Concern

  private

  def workflow
    @workflow ||= Workflow.where(workspace: current_workspace).find(params[:id])
  end

  def back_to_canvas(**flash) = redirect_to(workflow_path(workflow), **flash)
end
