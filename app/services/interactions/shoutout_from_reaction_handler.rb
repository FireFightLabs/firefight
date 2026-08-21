module Interactions
  class ShoutoutFromReactionHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = JSON.parse(interaction.action_value)
      incident = workspace.incidents.find(metadata["incident_id"])

      workspace.adapter.open_modal(trigger_id: interaction.trigger_id, view: Slack::Modals::Shoutout.build(incident))

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
