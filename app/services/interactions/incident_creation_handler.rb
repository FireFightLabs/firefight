module Interactions
  class IncidentCreationHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      submission = Slack::FormSubmission.new(
        workspace: workspace,
        form_slug: IncidentForm::SLUG_DECLARE,
        values: interaction.values
      ).parse

      if submission.errors.any?
        return {
          response_action: "errors",
          errors: { submission.first_error_block_id => submission.errors.first }
        }
      end

      attrs = submission.system_attrs
      severity = workspace.incident_severities.active.find_by!(slug: attrs["severity"])
      status = workspace.incident_statuses.default_status
      incident_type = attrs["incident_type"].present? ? workspace.incident_types.active.find_by(slug: attrs["incident_type"]) : nil
      # `visibility` is now a system field; absent when the field isn't on the form, in which case default to public.
      visibility = attrs["visibility"]

      incident = IncidentLifecycleService.new(workspace).create(
        declared_by: member,
        incident_status: status,
        incident_severity: severity,
        incident_type: incident_type,
        name: attrs["name"],
        summary: attrs["summary"],
        custom_fields: submission.custom_fields.presence || {},
        is_private: visibility == Incident::VISIBILITY_PRIVATE,
        source: Incident::SOURCE_SLACK,
        create_channel_sync: true
      )

      Rails.logger.info({
        event: "incident.creation_started",
        incident_id: incident.id,
        identifier: incident.identifier,
        workspace_id: workspace.id,
        severity: attrs["severity"]
      })

      { response_action: "update", view: Slack::Modals::IncidentCreated.build(incident, team_id: workspace.platform_id) }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })
      { response_action: "errors", errors: { field_severity_block: "Invalid severity selection. Please try again." } }
    rescue => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })
      { response_action: "errors", errors: { field_name_block: "Failed to create incident. Please try again." } }
    end
  end
end
