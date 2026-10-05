module Interactions
  # Reopen and Unassign on an item's message. Why it cannot be done is said to whoever clicked.
  class EditActionItemHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      action = IncidentAction.in_workspace(workspace).active.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      service = IncidentActionService.new(workspace)

      refusal = if interaction.action_id == Identifiers::REOPEN_ACTION
        service.reopen_action(action: action, reopened_by: member)
      else
        service.unassign_action(action: action, unassigned_by: member)
      end
      if refusal && interaction.channel_id
        workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal)
      end
      OpenModalRefresh.call(interaction, workspace)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
