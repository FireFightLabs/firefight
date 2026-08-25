module Interactions
  class CancelIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_canceled_error(workspace) if incident.incident_status.incident_lifecycle_stage.canceled?

      submission = workspace.adapter.parse_form_submission(
        form_slug: IncidentForm::SLUG_CANCEL,
        values: interaction.values,
        incident: incident
      )

      if submission.errors.any?
        return workspace.adapter.form_error_response(submission.first_error_field_key, submission.errors.first)
      end

      chosen = submission.system_attrs[IncidentSystemField::KEY_STATUS]
      status = (chosen.present? && workspace.incident_statuses.canceled.active.find_by(slug: chosen)) ||
               workspace.default_canceled_status

      system_attrs = submission.system_attrs
      attrs = { incident_status: status }
      attrs[:name] = system_attrs[IncidentSystemField::KEY_NAME] if system_attrs[IncidentSystemField::KEY_NAME].present?
      attrs[:summary] = system_attrs[IncidentSystemField::KEY_SUMMARY] if system_attrs[IncidentSystemField::KEY_SUMMARY].present?
      attrs[:custom_fields] = submission.custom_fields if submission.custom_fields.present?

      IncidentLifecycleService.new(workspace).change_status(
        incident,
        attrs,
        changed_by: member,
        # The summary a responder typed while cancelling is the explanation of
        # why, so it belongs in the message the channel sees.
        message: system_attrs[IncidentSystemField::KEY_SUMMARY].presence
      )
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.incident_cancel.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      nil
    end

    def self.already_canceled_error(workspace)
      workspace.adapter.form_error_response(IncidentSystemField::KEY_MESSAGE, "This incident is already canceled.")
    end
    private_class_method :already_canceled_error
  end
end
