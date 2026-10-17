# Removing a member from Settings, Members, and adding one back. Admins only, through the gateway like any workspace
# change.
class WorkspaceMembershipsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, update: %i[destroy restore]

  def destroy
    membership = current_workspace.workspace_memberships.find(params[:id])
    MembershipRemoval.remove!(membership, by: current_membership)
    redirect_to settings_members_path, notice: "#{membership.display_name} was removed from #{current_workspace.name}."
  rescue MembershipRemoval::Blocked => e
    redirect_to settings_members_path, alert: e.message
  end

  def restore
    membership = current_workspace.removed_memberships.find(params[:id])
    MembershipRemoval.restore!(membership)
    redirect_to settings_members_path, notice: "#{membership.display_name} was added back to #{current_workspace.name}."
  rescue MembershipRemoval::Blocked => e
    redirect_to settings_members_path, alert: e.message
  end
end
