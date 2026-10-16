module Interactions
  class ReopenIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_active_error(workspace) unless incident.terminal?

      reason = interaction.values.dig(Identifiers::REASON_BLOCK, Identifiers::REASON_INPUT, "value")

      IncidentLifecycleService.new(workspace).change_status(
        incident,
        { incident_status: workspace.default_live_status },
        changed_by: member,
        message: reason
      )

      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.reopen_incident.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      workspace.adapter.modal_errors_response({ Identifiers::REASON_BLOCK => Interactions::ModalCleanup::RECORD_GONE })
    end

    def self.already_active_error(workspace)
      workspace.adapter.modal_errors_response({ Identifiers::REASON_BLOCK => "This incident is already active." })
    end
    private_class_method :already_active_error
  end
end
