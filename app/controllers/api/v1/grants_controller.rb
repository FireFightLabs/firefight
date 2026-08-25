class Api::V1::GrantsController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    scope = current_workspace.ability_grants.includes(:action, :role, :principal).order(:created_at)
    if params[:principal_kind].present?
      principal = Ability::Principal.find!(current_workspace, params[:principal_kind], params.require(:principal_id))
      scope = scope.where(principal: principal)
    end
    @grants = scope
  end

  def create
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)
    principal = Ability::Principal.find!(current_workspace, params.require(:principal_kind), params.require(:principal_id))
    @grant = Ability::Grant.grant!(
      workspace: current_workspace, principal: principal, target: target_param,
      environment_ids: environment_ids_for(params[:environments]), expires_at: params[:expires_at]
    )
    render :show, status: @grant.previously_new_record? ? :created : :ok
  end

  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @grant = current_workspace.ability_grants.find(params[:id])
    @grant.rescope!(
      environment_ids: params.key?(:environments) ? environment_ids_for(params[:environments]) : @grant.environment_ids,
      expires_at: params.key?(:expires_at) ? params[:expires_at] : :unchanged
    )
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)
    current_workspace.ability_grants.find(params[:id]).destroy!
    head :no_content
  end

  private

  # Exactly one of an ability key or a permission set slug, which the grant
  # itself validates.
  def target_param
    if params[:permission_set].present?
      { role: current_workspace.ability_roles.find_by!(slug: params[:permission_set]) }
    else
      { action: Ability::Action.grantable_for(current_workspace).find_by!(key: params.require(:ability)) }
    end
  end
end
