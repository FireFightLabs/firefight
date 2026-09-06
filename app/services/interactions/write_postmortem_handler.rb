module Interactions
  # Same path as /ff postmortem.
  class WritePostmortemHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by(platform_user_id: interaction.user_id)

      text = if member
        PostmortemGenerationService.new(workspace).request!(incident, by: member).message
      else
        PostmortemGenerationService::UNKNOWN_MEMBER_MESSAGE
      end
      workspace.adapter.post_ephemeral(channel_id: incident.channel_id, user_id: interaction.user_id, text: text)
      nil
    end
  end
end
