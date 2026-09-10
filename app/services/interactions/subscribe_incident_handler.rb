module Interactions
  # A second click is answered, never undone, since a shared button must not mean two things.
  class SubscribeIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter
      )
      return nil unless member

      state = incident.subscribe!(member)
      SubscriptionNotice.post(workspace, incident, interaction, state)
    end
  end
end
