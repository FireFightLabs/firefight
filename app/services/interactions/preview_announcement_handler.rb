# Handles the "Preview Announcement" button click in the workspace setup flow
module Interactions
  class PreviewAnnouncementHandler
    extend WorkspaceFinding

    def self.execute(payload)
      workspace = find_workspace(payload)
      user_id = payload.dig("user", "id")
      channel_id = payload.dig("channel", "id")

      adapter = Slack::WorkspaceAdapter.new(workspace)
      adapter.post_preview_announcement(channel_id: channel_id, user_id: user_id)

      Rails.logger.info({
        event: "interactions.preview_posted",
        message: "Posted preview announcement",
        workspace_id: workspace.id,
        user_id: user_id,
        channel_id: channel_id
      })

      { response_action: "clear" }
    end
  end
end
