module Interactions
  class IncidentCreationHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      member = workspace.workspace_memberships.find_by(platform_user_id: interaction.user_id)

      unless member
        Rails.logger.error({
          event: "incident.creation_member_not_found",
          workspace_id: workspace.id,
          user_id: interaction.user_id
        })
        return workspace.adapter.form_error_response(IncidentSystemField::KEY_NAME, "We could not verify your account. Please try again or contact support.")
      end

      submission = workspace.adapter.parse_form_submission(
        form_slug: IncidentForm::SLUG_DECLARE,
        values: interaction.values
      )

      return workspace.adapter.form_error_response(submission.first_error_field_key, submission.errors.first) if submission.errors.any?

      attrs = submission.system_attrs
      severity = workspace.incident_severities.active.find_by!(slug: attrs["severity"])
      status = workspace.incident_statuses.default_status
      incident_type = attrs["incident_type"].present? ? workspace.incident_types.active.find_by(slug: attrs["incident_type"]) : nil
      # `visibility` is now a system field. Absent when the field isn't on the form, in which case default to public.
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

      workspace.adapter.form_update_response(workspace.adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATED, incident))
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error({ event: "incident.creation_severity_not_found", error: e.message })
      workspace.adapter.form_error_response(IncidentSystemField::KEY_SEVERITY, "Invalid severity selection. Please try again.")
    rescue => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })
      workspace.adapter.form_error_response(IncidentSystemField::KEY_NAME, "Failed to create incident. Please try again.")
    end
  end
end
