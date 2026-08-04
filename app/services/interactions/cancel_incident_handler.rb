module Interactions
  class CancelIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = Slack::PrivateMetadata.parse(interaction.private_metadata)
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_canceled_error if incident.incident_status.incident_lifecycle_stage.canceled?

      submission = Slack::FormSubmission.new(
        workspace: workspace,
        form_slug: IncidentForm::SLUG_CANCEL,
        values: interaction.values,
        incident: incident
      ).parse

      if submission.errors.any?
        return {
          response_action: "errors",
          errors: { submission.first_error_block_id => submission.errors.first }
        }
      end

      scope = workspace.incident_statuses.canceled.active.ordered
      chosen = submission.system_attrs[IncidentSystemField::KEY_STATUS]
      status = (chosen.present? && scope.find_by(slug: chosen)) || scope.first
      return no_status_error if status.nil?

      IncidentLifecycleService.new(workspace).cancel(
        incident,
        { incident_status: status, custom_fields: submission.custom_fields.presence || {} },
        changed_by: member
      )
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.incident_cancel.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      nil
    end

    def self.already_canceled_error
      { response_action: "errors", errors: { "field_message_block" => "This incident is already canceled." } }
    end
    private_class_method :already_canceled_error

    def self.no_status_error
      { response_action: "errors",
        errors: { "field_message_block" => "No canceled status is configured for this workspace." } }
    end
    private_class_method :no_status_error
  end
end
