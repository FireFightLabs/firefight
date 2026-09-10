# Unresolved @handles fall back to a paginated users.list lookup, too slow for
# Slack's 3s command budget on a large workspace.
class IncidentInviteJob < ApplicationJob
  queue_as :default

  def perform(workspace_id:, incident_id:, text:, channel_id:, user_id:)
    workspace = Workspace.find(workspace_id)
    incident = workspace.incidents.find(incident_id)
    IncidentInviteService.new(workspace).resolve_and_notify!(
      incident: incident,
      text: text,
      channel_id: channel_id,
      user_id: user_id
    )
  end
end
