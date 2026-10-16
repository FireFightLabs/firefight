module Interactions
  class UpdateSummaryHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      new_summary = interaction.values.dig(Identifiers::SUMMARY_BLOCK, Identifiers::SUMMARY_INPUT, "value")

      incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: member) do
        incident.update!(summary: new_summary)
      end

      SummaryUpdateWorkflow.start!(incident, context: {
        updated_by_platform_user_id: interaction.user_id
      })

      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.update_summary.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      workspace.adapter.modal_errors_response({ Identifiers::SUMMARY_BLOCK => Interactions::ModalCleanup::RECORD_GONE })
    end
  end
end
