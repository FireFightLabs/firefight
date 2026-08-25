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

  # Deciding is structurally human. The model takes a membership, so a
  # service key cannot resolve approvals whatever it was granted.
  def resolve(decision)
    authorize!(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE)
    unless Current.principal.is_a?(WorkspaceMembership)
      return render json: error_response("human_only", "Only a person can decide an approval. Use a personal token."), status: :forbidden
    end

    @approval = current_workspace.ability_approvals.find(params[:id])
    decision == :approve ? @approval.approve!(by: Current.principal) : @approval.deny!(by: Current.principal)
    ApprovalNotificationService.mark_resolved!(@approval)
    render :show
  end
end
