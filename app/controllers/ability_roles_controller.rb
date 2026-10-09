class AbilityRolesController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: :update, delete: :destroy

  def create
    role = current_workspace.ability_roles.create!(name: params.require(:name))
    redirect_to gateway_permissions_path, notice: "#{role.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # `action_ids` is the full set, not a delta, so an absent or empty list empties it.
  def update
    role = current_workspace.ability_roles.find(params[:id])
    role.sync_actions!(permitted_action_ids)

    redirect_to gateway_permissions_path, notice: "#{role.name} was updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Destroying the set revokes it everywhere it was granted. A built-in pack refuses, with the reason.
  def destroy
    role = current_workspace.ability_roles.find(params[:id])
    held = role.grants.exists?
    role.destroy_by_hand!
    redirect_to gateway_permissions_path, notice: held ? "#{role.name} was deleted and revoked from everyone who held it." : "#{role.name} was deleted."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def permitted_action_ids
    Ability::Action.grantable_for(current_workspace).where(id: Array(params[:action_ids])).pluck(:id)
  end
end
