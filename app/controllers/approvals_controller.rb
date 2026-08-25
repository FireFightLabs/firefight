# Resolution side of the approvals inbox (the page itself is
# settings#approvals). The model enforces role-at-click-time and
# self-approval rules on top of the gateway's answer.
class ApprovalsController < InertiaController
  authorizes Ability::Action::RESOURCE_APPROVALS, update: %i[approve deny]

  before_action :set_approval

  def approve
    resolve { @approval.approve!(by: current_membership) }
  end

  def deny
    resolve { @approval.deny!(by: current_membership) }
  end

  private

  def resolve
    yield
    ApprovalNotificationService.mark_resolved!(@approval)
    redirect_to settings_approvals_path
  rescue Ability::Approval::NotAllowed => e
    redirect_to settings_approvals_path, alert: e.message
  end

  def set_approval
    @approval = current_workspace.ability_approvals.find(params[:id])
  end
end
