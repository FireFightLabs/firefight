module Interactions
  class AddNewActionHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      workspace.adapter.open_create_action_modal(trigger_id: interaction.trigger_id, incident: incident, push: true)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
