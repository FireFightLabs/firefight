module Interactions
  class SetLeadHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.metadata.incident_id)
      acting_member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      blocked_reason = incident.lead_assignment_blocked_reason
      return workspace.adapter.modal_errors_response({ Identifiers::LEAD_BLOCK => blocked_reason }) if blocked_reason

      selected_user_id = interaction.values.dig(Identifiers::LEAD_BLOCK, Identifiers::LEAD_SELECT, "selected_user")
      selected_member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: selected_user_id,
        adapter: workspace.adapter
      )
      return provision_error(workspace, Identifiers::LEAD_BLOCK) unless selected_member

      IncidentLifecycleService.new(workspace).assign_lead(incident, selected_member, changed_by: acting_member)

      nil
    end

    def self.provision_error(workspace, block_id)
      workspace.adapter.modal_errors_response({ block_id => "Couldn't load that user's profile from Slack. Please try again in a moment." })
    end
    private_class_method :provision_error
  end
end
