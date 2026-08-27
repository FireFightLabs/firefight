class Api::V1::PermissionSetsController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @permission_sets = current_workspace.ability_roles.order(:name).includes(:grants, actions: { source: :integration })
  end

  def create
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)
    @permission_set = current_workspace.ability_roles.create!(name: params.require(:name))
    @permission_set.sync_actions!(action_ids_for(params[:abilities])) if params.key?(:abilities)
    render :show, status: :created
  end

  # `abilities` is the set's full contents, not a delta.
  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @permission_set = find_set!
    @permission_set.update!(name: params[:name]) if params.key?(:name)
    @permission_set.sync_actions!(action_ids_for(params[:abilities])) if params.key?(:abilities)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)
    find_set!.destroy!
    head :no_content
  end

  private

  def find_set!
    current_workspace.ability_roles.find_by!(slug: params[:id])
  end

  def action_ids_for(keys)
    Ability::Action.grantable_for(current_workspace).where(key: Array(keys).map(&:to_s)).pluck(:id)
  end
end
