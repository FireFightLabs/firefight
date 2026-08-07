module Interactions
  class ClaimRunbookStepHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value.to_s)
      incident_runbook = workspace.incident_runbooks.find(payload["incident_runbook_id"])
      step = incident_runbook.runbook.runbook_steps.find(payload["step_id"])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      IncidentActionService.new(workspace).claim_step(
        incident: incident_runbook.incident,
        runbook_step: step,
        claimed_by: member
      )

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    end
  end
end
