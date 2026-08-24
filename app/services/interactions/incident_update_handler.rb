module Interactions
  class IncidentUpdateHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
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

      # The modal offers every enabled status, so a responder picking a closed
      # or canceled one gets the real close or cancel, not a silent update.
      IncidentLifecycleService.new(workspace).change_status(
        incident,
        attrs,
        changed_by: member,
        message: message
      )

      schedule_next_update_reminder(incident) if attrs[:next_update_at].present?
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.incident_update.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_STATUS) => "Something went wrong. Please close this modal and try again." } }
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
      attrs.merge(next_update_attrs(submission))
    end
    private_class_method :build_update_attrs

    # Reads `next_update` from the form submission. If the field isn't on the
    # configured form at all, leave `next_update_at` untouched (the workspace
    # has opted out of update reminders). If it's on the form but the user
    # picked nothing, clear it. It rides along with the status rather than
    # being written afterwards, so a terminal status wins. Incident::Lifecycle
    # clears next_update_at in the same save, and a later write would undo it.
    def self.next_update_attrs(submission)
      return {} unless submission.includes_system_key?(IncidentSystemField::KEY_NEXT_UPDATE)

      minutes = submission.system_attrs[IncidentSystemField::KEY_NEXT_UPDATE]
      { next_update_at: minutes.present? ? Time.current + minutes.to_i.minutes : nil }
    end
    private_class_method :next_update_attrs

    # Only called when the responder asked for a reminder, so a blank
    # next_update_at here means the save cleared it. The incident is over and
    # nobody is waiting on a next update.
    def self.schedule_next_update_reminder(incident)
      next_update_at = incident.next_update_at
      return if next_update_at.blank?

      IncidentUpdateReminderJob.set(wait: next_update_at - Time.current)
        .perform_later(incident.id, next_update_at.iso8601)
    end
    private_class_method :schedule_next_update_reminder
  end
end
