module Interactions
  class PreviewAnnouncementHandler
    def self.execute(interaction)
      workspace = interaction.workspace

      adapter = Slack::WorkspaceAdapter.new(workspace)
      adapter.post_preview_announcement(channel_id: interaction.channel_id, user_id: interaction.user_id)

      Rails.logger.info({
        event: "interactions.preview_posted",
        message: "Posted preview announcement",
        workspace_id: workspace.id,
        user_id: interaction.user_id,
        channel_id: interaction.channel_id
      })

      { response_action: "clear" }
    end
  end
end
