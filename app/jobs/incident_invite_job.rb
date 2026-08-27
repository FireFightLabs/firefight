# resolve_invitees can be slow on large workspaces, when the command contains
# unresolved @handles it falls back to a paginated users.list lookup. Running
# the full resolve + invite + summary flow async keeps the slash command
# response well under Slack's 3s budget regardless of workspace size.
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
