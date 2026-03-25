module Interactions
  class SetLeadSelfHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      IncidentLifecycleService.new(workspace).assign_lead(incident, member, changed_by: member)

      nil
    end
  end
end
