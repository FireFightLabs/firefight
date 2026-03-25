module Interactions
  class SetLeadHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.private_metadata)
      acting_member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      selected_user_id = interaction.values.dig("lead_block", "lead_select", "selected_user")
      selected_member = workspace.workspace_memberships.find_by!(platform_user_id: selected_user_id)

      IncidentLifecycleService.new(workspace).assign_lead(incident, selected_member, changed_by: acting_member)

      nil
    end
  end
end
