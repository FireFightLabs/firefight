module Interactions
  class IncidentUpdateHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      submission = workspace.adapter.parse_form_submission(
        form_slug: IncidentForm::SLUG_UPDATE,
        values: interaction.values,
        incident: incident
      )

      if submission.errors.any?
        return workspace.adapter.form_error_response(submission.first_error_field_key, submission.errors.first)
      end

      form = IncidentFormSubmission.new(
        workspace,
        incident: incident,
        form_slug: IncidentForm::SLUG_UPDATE,
        system_attrs: submission.system_attrs,
        custom_fields: submission.custom_fields,
        visible_system_keys: submission.visible_system_keys
      )
      attrs = form.attributes
      message = form.message

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
      workspace.adapter.form_error_response(IncidentSystemField::KEY_STATUS, "Something went wrong. Please close this modal and try again.")
    end

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
