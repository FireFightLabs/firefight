# The gateway decides who may decide a request, approvals access or being named on a workflow's Approval step for that
# request. The model enforces role at click time and self-approval on top of the gateway's answer.
class ApprovalsController < InertiaController
  authorizes Ability::Action::RESOURCE_APPROVALS, update: %i[approve deny], scope: :decision_scope

  def approve
    resolve("You approved #{asker}'s request. #{ApprovalResumption.approved_words(approval)}") { approval.approve!(by: current_membership) }
  end

  def deny
    resolve("You denied #{asker}'s request.") { approval.deny!(by: current_membership) }
  end

  private

  def resolve(done)
    yield
    ApprovalNotificationService.mark_resolved!(approval)
    redirect_to gateway_approvals_path, notice: done
  rescue Ability::Approval::NotAllowed => e
    redirect_to gateway_approvals_path, alert: e.message
  end

  def asker = approval.principal_own_name

  def approval = @approval ||= current_workspace.ability_approvals.find(params[:id])

  def decision_scope = approval.decision_scope
end
