module Interactions
  class UpdateSummaryHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.private_metadata)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      new_summary = interaction.values.dig("summary_block", "summary_input", "value")

      incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: member) do
        incident.update!(summary: new_summary)
      end

      SummaryUpdateWorkflow.start!(incident, context: {
        updated_by_platform_user_id: interaction.user_id
      })

      nil
    end
  end
end
