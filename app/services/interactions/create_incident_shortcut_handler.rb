module Interactions
  class CreateIncidentShortcutHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace

      adapter = workspace.adapter
      adapter.open_modal(trigger_id: interaction.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATION))

      Rails.logger.info({
        event: "shortcut.create_incident",
        workspace_id: workspace.id,
        user_id: interaction.user_id
      })

      nil
    rescue AdapterError::TriggerExpired
      Rails.logger.warn({
        event: "shortcut.trigger_expired",
        workspace_id: workspace&.id,
        trigger_id: interaction.trigger_id
      })

      {
        response_action: "errors",
        errors: { base: "This shortcut has expired. Please try again." }
      }
    end
  end
end
