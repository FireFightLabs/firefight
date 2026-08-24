module Interactions
  class SendIncidentUpdateButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      ModalOpener.open(
        :update,
        workspace: workspace,
        incident: incident,
        trigger_id: interaction.trigger_id,
        user_id: interaction.user_id
      )

      nil
    rescue AdapterError::TriggerExpired
      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.send_incident_update.record_not_found", error: e.message })
      nil
    end
  end
end
