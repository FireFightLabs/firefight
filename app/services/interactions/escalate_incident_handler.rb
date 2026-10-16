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
        escalated_to: workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::ESCALATE_TO_BLOCK, input_id: Identifiers::ESCALATE_TO_SELECT, kind: PlatformAdapter::Input::USER),
        reason: workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::REASON_BLOCK, input_id: Identifiers::REASON_INPUT, kind: PlatformAdapter::Input::TEXT),
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
