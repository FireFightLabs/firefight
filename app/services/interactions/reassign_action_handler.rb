module Interactions
  class ReassignActionHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      action_id = interaction.block_id.to_s.delete_prefix(Identifiers::ACTION_BLOCK_PREFIX)
      action = IncidentAction.in_workspace(workspace).find(action_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      assignee = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.selected_user, adapter: workspace.adapter
      )
      return nil unless assignee

      IncidentActionService.new(workspace).reassign_action(
        action: action, assignee: assignee, reassigned_by: member
      )

      OpenModalRefresh.call(interaction, workspace)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
