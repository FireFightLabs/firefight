module Interactions
  # Create issue on an item's message, or trying it again after it failed. The issue is opened in a job as whoever
  # clicked, and the message redraws once it is there. Why it cannot be opened is said to whoever clicked.
  class CreateActionIssueHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      action = IncidentAction.in_workspace(workspace).active.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      refusal = IssueSyncService.new(workspace).request(action, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
