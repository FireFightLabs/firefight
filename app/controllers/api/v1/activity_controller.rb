class Api::V1::ActivityController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    scope = current_workspace.ability_invocations.order(created_at: :desc)
    scope = scope.where(decision: params[:decision].to_s) if params[:decision].present?
    scope = scope.where(action_key: params[:ability].to_s) if params[:ability].present?
    @invocations, @pagination = paginate(scope)
  end
end
