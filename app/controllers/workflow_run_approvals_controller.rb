# Decides a workflow's Approval step from the run's page, as the Approvals page decides any request. The model enforces
# who may decide at click time, and a refusal says why in its words.
class WorkflowRunApprovalsController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_APPROVALS, update: %i[approve deny]

  def approve
    decide("You approved #{workflow.name}'s request. The run goes on.") { approval.approve!(by: current_membership) }
  end

  def deny
    decide("You denied #{workflow.name}'s request.") { approval.deny!(by: current_membership) }
  end

  private

  def decide(done)
    yield
    ApprovalNotificationService.mark_resolved!(approval)
    back_to_run(notice: done)
  rescue Ability::Approval::NotAllowed => error
    back_to_run(alert: "#{error.message.upcase_first}.")
  end

  def run = @run ||= workflow.runs.find(params[:run_id])

  def approval
    @approval ||= current_workspace.ability_approvals.where(workflow_run_id: run.id, action_key: Ability::Action::WORKFLOW_APPROVAL).find(params[:approval_id])
  end

  def back_to_run(**flash) = redirect_to(workflow_path(workflow, WorkflowCanvasController::RUN_QUERY_PARAM => run.id), **flash)
end
