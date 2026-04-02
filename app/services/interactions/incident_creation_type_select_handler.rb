module Interactions
  class IncidentCreationTypeSelectHandler
    def self.execute(interaction)
      workspace = interaction.workspace

      selected_type_slug = interaction.values.dig(
        "field_incident_type_block",
        Identifiers::INCIDENT_CREATION_TYPE_SELECT,
        "selected_option", "value"
      )

      selected_severity_slug = interaction.values.dig(
        "field_severity_block",
        Identifiers::INCIDENT_CREATION_SEVERITY_SELECT,
        "selected_option", "value"
      )

      selected_type = workspace.incident_types.active.find_by(slug: selected_type_slug)

      workspace.adapter.update_incident_creation_modal(
        view_id: interaction.view["id"],
        selected_severity_slug: selected_severity_slug,
        selected_type_id: selected_type&.id
      )

      nil
    rescue => e
      Rails.logger.error({ event: "incident_creation.type_select_error", error: e.message })
      nil
    end
  end
end
