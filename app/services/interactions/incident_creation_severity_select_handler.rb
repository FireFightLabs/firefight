module Interactions
  class IncidentCreationSeveritySelectHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter

      adapter.update_incident_creation_modal(
        view_id: interaction.view["id"],
        selected_severity_slug: interaction.selected_value
      )

      nil
    rescue => e
      Rails.logger.error({ event: "incident_creation.severity_select_error", error: e.message })
      nil
    end
  end
end
