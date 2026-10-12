class AbilityRolesController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: %i[update members], delete: :destroy

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

  # Who among the members can read or change through a connection's pack: everyone, nobody or the people chosen. Back to
  # the page that asked, since Who can do what is in setup as well as on the Permissions screen.
  def members
    role = current_workspace.ability_roles.find(params[:id])
    choice = params[:choice].to_s
    people = current_workspace.workspace_memberships.includes(:user).where(id: Array(params[:people_ids])).sort_by(&:display_name)
    role.let_members!(choice, people: people, by: current_membership)

    redirect_back fallback_location: gateway_permissions_path, notice: role.member_access_notice(choice, people)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
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
