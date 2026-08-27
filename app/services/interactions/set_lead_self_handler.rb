module Interactions
  class SetLeadSelfHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      blocked_reason = incident.lead_assignment_blocked_reason
      return TerminalNotice.post(workspace, incident, interaction.user_id, blocked_reason) if blocked_reason

      IncidentLifecycleService.new(workspace).assign_lead(incident, member, changed_by: member)

      nil
    end
  end
end
