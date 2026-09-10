module Interactions
  # Both places this button appears are only seen by the person it belongs to.
  class UnsubscribeIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      state = incident.unsubscribe!(member)
      SubscriptionNotice.post(workspace, incident, interaction, state)
    end
  end
end
