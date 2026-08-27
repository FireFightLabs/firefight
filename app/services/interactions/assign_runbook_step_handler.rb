module Interactions
  class AssignRunbookStepHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident_runbook = workspace.incident_runbooks.find(metadata.incident_runbook_id)
      step_id = interaction.block_id.to_s.delete_prefix(Identifiers::RUNBOOK_STEP_BLOCK_PREFIX)
      step = incident_runbook.runbook.runbook_steps.find(step_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      assignee = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.selected_user, adapter: workspace.adapter
      )
      return nil unless assignee

      IncidentActionService.new(workspace).assign_step(
        incident: incident_runbook.incident,
        runbook_step: step,
        assignee: assignee,
        assigned_by: member
      )

      OpenModalRefresh.call(interaction, workspace)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
