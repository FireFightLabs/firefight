module Interactions
  class SetLeadHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.private_metadata)
      acting_member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      selected_user_id = interaction.values.dig("lead_block", "lead_select", "selected_user")
      selected_member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: selected_user_id,
        adapter: workspace.adapter
      )
      return provision_error("lead_block") unless selected_member

      IncidentLifecycleService.new(workspace).assign_lead(incident, selected_member, changed_by: acting_member)

      nil
    end

    def self.provision_error(block_id)
      { response_action: "errors", errors: { block_id => "Couldn't load that user's profile from Slack. Please try again in a moment." } }
    end
    private_class_method :provision_error
  end
end
