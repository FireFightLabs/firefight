module Interactions
  class CreateActionFromReactionHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = JSON.parse(interaction.action_value)
      incident = workspace.incidents.find(metadata["incident_id"])

      private_metadata = {
        incident_id: incident.id,
        source_message_text: metadata["source_message_text"],
        source_message_link: metadata["source_message_link"]
      }.to_json

      adapter = WorkspaceAdapter.for(workspace)
      adapter.open_create_action_modal(
        trigger_id: interaction.trigger_id,
        incident: incident,
        private_metadata: private_metadata
      )

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
