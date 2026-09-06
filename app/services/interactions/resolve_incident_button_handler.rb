module Interactions
  # The Resolve button on the quick actions. Opens the same close dialog as
  # /ff resolve, so a workspace's required closing fields are still asked.
  class ResolveIncidentButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      unless incident.active?
        return TerminalNotice.post(workspace, incident, interaction.user_id, "#{incident.identifier} is already over.")
      end

      ModalOpener.open(
        :close,
        workspace: workspace,
        incident: incident,
        trigger_id: interaction.trigger_id,
        user_id: interaction.user_id
      )
      nil
    end
  end
end
