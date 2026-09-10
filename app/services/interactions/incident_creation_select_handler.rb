module Interactions
  # One handler for every dispatching select, so adding a source is a block change.
  class IncidentCreationSelectHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      interaction.workspace.adapter.update_incident_creation_modal(
        view_id: interaction.view["id"],
        state: interaction.values || {},
        private_metadata: interaction.private_metadata,
        test: interaction.metadata.test
      )

      nil
    rescue StandardError => e
      Rails.logger.error({ event: "incident_creation.select_error", error: e.message })
      nil
    end
  end
end
