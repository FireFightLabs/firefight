module Interactions
  class IncidentCreationHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      values = interaction.values
      name = values.dig("name_block", "name_input", "value")
      severity_slug = values.dig("severity_block", Identifiers::INCIDENT_CREATION_SEVERITY_SELECT, "selected_option", "value")
      summary = values.dig("summary_block", "summary_input", "value")
      visibility = values.dig("visibility_block", "visibility_select", "selected_option", "value")

      severity = workspace.incident_severities.active.find_by!(slug: severity_slug)
      status = workspace.incident_statuses.default_status

      incident = Incident.create!(
        workspace: workspace,
        declared_by: member,
        incident_status: status,
        incident_severity: severity,
        name: name,
        summary: summary,
        is_private: visibility == Incident::VISIBILITY_PRIVATE
      )

      IncidentCreationService.new(workspace).create_channel(incident)
      IncidentCreationWorkflow.start!(incident)

      Rails.logger.info({
        event: "incident.creation_started",
        incident_id: incident.id,
        identifier: incident.identifier,
        workspace_id: workspace.id,
        severity: severity_slug
      })

      adapter = workspace.adapter
      { response_action: "update", view: adapter.build_incident_created_view(incident) }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })

      {
        response_action: "errors",
        errors: { severity_block: "Invalid severity selection. Please try again." }
      }
    rescue => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })

      {
        response_action: "errors",
        errors: { name_block: "Failed to create incident. Please try again." }
      }
    end
  end
end
