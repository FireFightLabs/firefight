module Interactions
  class ShoutoutFromReactionHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = JSON.parse(interaction.action_value)
      incident = workspace.incidents.find(metadata["incident_id"])

      adapter = WorkspaceAdapter.for(workspace)
      adapter.open_shoutout_modal(trigger_id: interaction.trigger_id, incident: incident)

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
