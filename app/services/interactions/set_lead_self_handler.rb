module Interactions
  class SetLeadSelfHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      incident.record_change!(IncidentEvent::LEAD_ASSIGNED, changed_by: member) do
        incident.lead = member
      end

      LeadAssignmentWorkflow.start!(incident, context: {
        lead_platform_user_id: interaction.user_id
      })

      nil
    end
  end
end
