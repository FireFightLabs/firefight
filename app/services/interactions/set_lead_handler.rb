module Interactions
  class SetLeadHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.private_metadata)
      acting_member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      selected_user_id = interaction.values.dig("lead_block", "lead_select", "selected_user")
      selected_member = workspace.workspace_memberships.find_by!(platform_user_id: selected_user_id)

      incident.record_change!(IncidentEvent::LEAD_ASSIGNED, changed_by: acting_member) do
        incident.lead = selected_member
      end

      LeadAssignmentWorkflow.start!(incident, context: {
        lead_platform_user_id: selected_user_id
      })

      nil
    end
  end
end
