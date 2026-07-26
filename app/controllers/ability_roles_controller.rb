class AbilityRolesController < InertiaController
  before_action :require_authentication
  before_action :require_admin!

  def create
    current_workspace.ability_roles.create!(name: params.require(:name))
    redirect_to settings_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  def update
    role = current_workspace.ability_roles.find(params[:id])
    role.update!(name: params[:name]) if params[:name].present?
    role.sync_actions!(permitted_action_ids) if params.key?(:action_ids)

    redirect_to settings_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Revoking the set revokes it everywhere it was granted, which is the point
  # of granting a set rather than its actions one by one.
  def destroy
    current_workspace.ability_roles.find(params[:id]).destroy!
    redirect_to settings_permissions_path
  end

  private

  def permitted_action_ids
    Ability::Action.where(workspace_id: [ nil, current_workspace.id ])
                   .where(id: Array(params[:action_ids]))
                   .pluck(:id)
  end
end
