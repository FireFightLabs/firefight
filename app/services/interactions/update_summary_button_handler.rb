module Interactions
  class UpdateSummaryButtonHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      SummaryModalOpener.open(
        workspace: workspace,
        incident: incident,
        trigger_id: interaction.trigger_id,
        user_id: interaction.user_id
      )
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
