class Api::V1::ApprovalsController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_READ)
    scope = current_workspace.ability_approvals.order(created_at: :desc)
    scope = scope.where(status: params[:status].to_s) if params[:status].present?
    @approvals, @pagination = paginate(scope)
  end

  def show
    authorize!(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_READ)
    @approval = current_workspace.ability_approvals.find(params[:id])
  end

  def approve
    resolve(:approve)
  end

  def deny
    resolve(:deny)
  end

  private

  # The model decides who may resolve, a person with the role or named on the rule,
  # or an agent the rule allows.
  def resolve(decision)
    authorize!(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE)
    @approval = current_workspace.ability_approvals.find(params[:id])
    decision == :approve ? @approval.approve!(by: Current.principal) : @approval.deny!(by: Current.principal)
    ApprovalNotificationService.mark_resolved!(@approval)
    render :show
  end
end
