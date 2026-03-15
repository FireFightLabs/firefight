module Interactions
  class LoadMoreTimelineHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value || "{}")
      incident = workspace.incidents.find(payload["incident_id"])
      limit = payload["limit"].to_i
      limit = Commands::Firefight::TimelineHandler::DEFAULT_LIMIT if limit <= 0

      response = Commands::Firefight::TimelineHandler.build_response(incident, limit: limit)

      workspace.adapter.post_ephemeral(
        channel_id: interaction.channel_id || incident.channel_id,
        user_id: interaction.user_id,
        text: response[:text],
        blocks: response[:blocks]
      )

      nil
    rescue JSON::ParserError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
