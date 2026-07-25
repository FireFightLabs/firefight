# Dashboard side of the approval flow: list pending requests, resolve them.
# The model enforces role-at-click-time and self-approval rules; endpoints
# only require a signed-in member.
class ApprovalsController < InertiaController
  before_action :require_authentication
  before_action :set_approval, only: [ :approve, :deny ]

  def index
    approvals = current_workspace.ability_approvals.pending.order(created_at: :desc).map do |approval|
      {
        id: approval.id, principal: approval.principal_label, action_key: approval.action_key,
        scope: approval.scope, params: approval.params, required_role: approval.required_role,
        requested_at: approval.created_at
      }
    end
    render json: { approvals: approvals }
  end

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
    render json: { id: @approval.id, status: @approval.status }
  rescue Ability::Approval::NotAllowed => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def set_approval
    @approval = current_workspace.ability_approvals.find(params[:id])
  end
end
