module Interactions
  class IncidentUpdateHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = Slack::PrivateMetadata.parse(interaction.private_metadata)
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      submission = Slack::FormSubmission.new(
        workspace: workspace,
        form_slug: IncidentForm::SLUG_UPDATE,
        values: interaction.values,
        incident: incident
      ).parse

      if submission.errors.any?
        return {
          response_action: "errors",
          errors: { submission.first_error_block_id => submission.errors.first }
        }
      end

      attrs = build_update_attrs(workspace, incident, submission)
      message = submission.system_attrs[IncidentSystemField::KEY_MESSAGE]

      IncidentLifecycleService.new(workspace).update(
        incident,
        attrs,
        changed_by: member,
        message: message
      )

      apply_next_update_reminder(incident, submission)
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.incident_update.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "field_status_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.build_update_attrs(workspace, incident, submission)
      system_attrs = submission.system_attrs

      new_status = system_attrs["status"].present? ? workspace.incident_statuses.active.find_by!(slug: system_attrs["status"]) : incident.incident_status
      new_severity = system_attrs["severity"].present? ? workspace.incident_severities.active.find_by!(slug: system_attrs["severity"]) : incident.incident_severity

      new_type = if submission.includes_system_key?(IncidentSystemField::KEY_INCIDENT_TYPE)
        system_attrs["incident_type"].present? ? workspace.incident_types.active.find_by!(slug: system_attrs["incident_type"]) : nil
      else
        incident.incident_type
      end

      attrs = { incident_status: new_status, incident_severity: new_severity, incident_type: new_type }
      # Only the submitted fields. Values are rows now, so writing a subset
      # leaves the rest untouched without reading them back first.
      attrs[:custom_fields] = submission.custom_fields if submission.custom_fields.present?
      attrs
    end
    private_class_method :build_update_attrs

    # Reads `next_update` from the form submission. If the field isn't on the
    # configured form at all, leave `next_update_at` untouched (the workspace
    # has opted out of update reminders). If it's on the form but the user
    # picked nothing, clear it.
    def self.apply_next_update_reminder(incident, submission)
      return unless submission.includes_system_key?(IncidentSystemField::KEY_NEXT_UPDATE)

      next_update_minutes = submission.system_attrs["next_update"]

      if next_update_minutes.present?
        incident.update!(next_update_at: Time.current + next_update_minutes.to_i.minutes)
        IncidentUpdateReminderJob.set(wait: next_update_minutes.to_i.minutes).perform_later(incident.id, incident.next_update_at.iso8601)
      else
        incident.update!(next_update_at: nil)
      end
    end
    private_class_method :apply_next_update_reminder
  end
end
