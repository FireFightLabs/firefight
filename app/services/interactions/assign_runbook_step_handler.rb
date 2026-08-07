module Interactions
  class AssignRunbookStepHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident_runbook = workspace.incident_runbooks.find(interaction.private_metadata)
      step_id = interaction.block_id.to_s.delete_prefix(Identifiers::RUNBOOK_STEP_BLOCK_PREFIX)
      step = incident_runbook.runbook.runbook_steps.find(step_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      assignee = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.selected_user, adapter: workspace.adapter
      )
      return nil unless assignee

      incident = incident_runbook.incident
      service = IncidentActionService.new(workspace)
      existing = incident.incident_actions.active.find_by(runbook_step: step)

      if existing
        service.reassign_action(action: existing, assignee: assignee, reassigned_by: member)
      else
        service.create_action(
          incident: incident,
          created_by: member,
          action_type: IncidentAction::ACTION_TYPE_ACTION,
          description: step.title,
          assignee: assignee,
          runbook_step: step
        )
      end

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
