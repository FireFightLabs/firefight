module Interactions
  class IncidentCreationHandler
    extend WorkspaceFinding

    def self.execute(payload)
      workspace = find_workspace(payload)
      user_id = payload.dig("user", "id")
      member = workspace.workspace_memberships.find_by!(platform_user_id: user_id)

      values = payload.dig("view", "state", "values")
      name = values.dig("name_block", "name_input", "value")
      severity_slug = values.dig("severity_block", "severity_select", "selected_option", "value")
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
        is_private: visibility == "private"
      )

      IncidentCreationWorkflow.start!(incident)

      Rails.logger.info({
        event: "incident.creation_started",
        incident_id: incident.id,
        identifier: incident.identifier,
        workspace_id: workspace.id,
        severity: severity_slug
      })

      nil
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
