module Interactions
  class TimelinePageHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value || "{}")
      incident = workspace.incidents.find(payload["incident_id"])

      view_id = interaction.view&.dig("id")
      return nil unless view_id

      workspace.adapter.update_timeline_modal(view_id: view_id, incident: incident, offset: payload["offset"].to_i)
      nil
    rescue JSON::ParserError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
