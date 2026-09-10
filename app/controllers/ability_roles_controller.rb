class AbilityRolesController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: :update, delete: :destroy

  def create
    current_workspace.ability_roles.create!(name: params.require(:name))
    redirect_to gateway_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # `action_ids` is the full set, not a delta, so an absent or empty list empties it.
  def update
    current_workspace.ability_roles.find(params[:id]).sync_actions!(permitted_action_ids)

    redirect_to gateway_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Destroying the set revokes it everywhere it was granted.
  def destroy
    current_workspace.ability_roles.find(params[:id]).destroy!
    redirect_to gateway_permissions_path
  end

  private

  def permitted_action_ids
    Ability::Action.grantable_for(current_workspace).where(id: Array(params[:action_ids])).pluck(:id)
  end
end
