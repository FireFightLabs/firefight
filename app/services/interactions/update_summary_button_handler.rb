module Interactions
  class UpdateSummaryButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      ModalOpener.open(
        :summary,
        workspace: workspace,
        incident: incident,
        trigger_id: interaction.trigger_id,
        user_id: interaction.user_id
      )
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
