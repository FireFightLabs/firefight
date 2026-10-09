# The model enforces role at click time and self-approval on top of the gateway's answer.
class ApprovalsController < InertiaController
  authorizes Ability::Action::RESOURCE_APPROVALS, update: %i[approve deny]

  before_action :set_approval

  def approve
    resolve("You approved #{asker}'s request. They can run it now.") { @approval.approve!(by: current_membership) }
  end

  def deny
    resolve("You denied #{asker}'s request.") { @approval.deny!(by: current_membership) }
  end

  private

  def resolve(done)
    yield
    ApprovalNotificationService.mark_resolved!(@approval)
    redirect_to gateway_approvals_path, notice: done
  rescue Ability::Approval::NotAllowed => e
    redirect_to gateway_approvals_path, alert: e.message
  end

  def asker = @approval.principal&.actor_display_name || "the person"

  def set_approval
    @approval = current_workspace.ability_approvals.find(params[:id])
  end
end
