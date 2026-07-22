module Interactions
  class ApplyRunbookHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident_runbook = workspace.incident_runbooks.find(interaction.action_value)
      return nil if incident_runbook.applied?

      ApplyRunbookJob.perform_later(
        workspace_id: workspace.id,
        incident_runbook_id: incident_runbook.id,
        user_id: interaction.user_id
      )

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
