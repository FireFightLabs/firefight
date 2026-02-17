module Interactions
  class AddNewFollowupHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      adapter = WorkspaceAdapter.for(workspace)
      adapter.open_create_followup_modal(trigger_id: interaction.trigger_id, incident: incident, push: true)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
