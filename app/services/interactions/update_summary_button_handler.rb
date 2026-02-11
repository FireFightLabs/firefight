module Interactions
  class UpdateSummaryButtonHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      adapter = WorkspaceAdapter.for(workspace)
      adapter.open_summary_modal(trigger_id: interaction.trigger_id, incident: incident)

      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
