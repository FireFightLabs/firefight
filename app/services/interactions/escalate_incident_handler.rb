module Interactions
  class EscalateIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      blocked_reason = incident.escalation_blocked_reason
      return workspace.adapter.modal_errors_response({ Identifiers::ESCALATE_TO_BLOCK => blocked_reason }) if blocked_reason

      IncidentLifecycleService.new(workspace).escalate(
        incident,
        escalated_to: interaction.values.dig(Identifiers::ESCALATE_TO_BLOCK, Identifiers::ESCALATE_TO_SELECT, "selected_user"),
        reason: interaction.values.dig(Identifiers::REASON_BLOCK, Identifiers::REASON_INPUT, "value"),
        changed_by: member
      )

      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.escalate_incident.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      workspace.adapter.modal_errors_response({ Identifiers::ESCALATE_TO_BLOCK => Interactions::ModalCleanup::RECORD_GONE })
    end
  end
end
