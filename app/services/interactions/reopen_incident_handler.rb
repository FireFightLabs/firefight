module Interactions
  class ReopenIncidentHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_active_error unless incident.terminal?

      reason = interaction.values.dig("reason_block", "reason_input", "value")
      live_statuses = workspace.incident_statuses.active.live
      default_status = live_statuses.find_by(is_default: true) || live_statuses.ordered.first

      IncidentLifecycleService.new(workspace).change_status(
        incident,
        { incident_status: default_status },
        changed_by: member,
        message: reason
      )

      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.reopen_incident.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "reason_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.already_active_error
      { response_action: "errors", errors: { "reason_block" => "This incident is already active." } }
    end
    private_class_method :already_active_error
  end
end
