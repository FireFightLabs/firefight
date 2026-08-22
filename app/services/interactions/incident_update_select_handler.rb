module Interactions
  # The status select on the update dialog dispatches so the modal re-renders
  # against what the responder has just picked. A status that ends the incident
  # takes the next update timer off the form rather than asking for a time that
  # is then discarded.
  class IncidentUpdateSelectHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = Slack::PrivateMetadata.parse(interaction.private_metadata)
      incident = workspace.incidents.find(metadata.incident_id)

      workspace.adapter.update_incident_update_modal(
        view_id: interaction.view_id,
        incident: incident,
        state: interaction.values || {},
        private_metadata: interaction.private_metadata
      )

      nil
    rescue StandardError => e
      Rails.logger.error({ event: "incident_update.select_error", error: e.message })
      nil
    end
  end
end
