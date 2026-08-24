module Interactions
  class ClaimRunbookStepHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value.to_s)
      incident_runbook = workspace.incident_runbooks.find(payload["incident_runbook_id"])
      step = incident_runbook.runbook.runbook_steps.find(payload["step_id"])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      IncidentActionService.new(workspace).assign_step(
        incident: incident_runbook.incident,
        runbook_step: step,
        assignee: member,
        assigned_by: member
      )

      OpenModalRefresh.call(interaction, workspace)
      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    end
  end
end
