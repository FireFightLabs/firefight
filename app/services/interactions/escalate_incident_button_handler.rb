module Interactions
  class EscalateIncidentButtonHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      ModalOpener.open(
        :escalate,
        workspace: workspace,
        incident: incident,
        trigger_id: interaction.trigger_id,
        user_id: interaction.user_id
      )

      nil
    rescue AdapterError::TriggerExpired
      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.escalate_incident_button.record_not_found", error: e.message })
      nil
    end
  end
end
