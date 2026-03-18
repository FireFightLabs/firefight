module Interactions
  class LoadMoreTimelineHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value || "{}")
      incident = workspace.incidents.find(payload["incident_id"])
      limit = payload["limit"].to_i
      limit = Commands::Firefight::TimelineHandler::DEFAULT_LIMIT if limit <= 0

      view_id = interaction.view&.dig("id")
      return nil unless view_id

      workspace.adapter.update_timeline_modal(view_id: view_id, incident: incident, limit: limit)
      nil
    rescue JSON::ParserError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
