# Service for handling Slack interactive components
# Processes button clicks, modal submissions, and other interactions
class SlackInteractionsService
  # Handle preview announcement button click
  #
  # @param payload [Hash] Slack interaction payload
  # @return [Hash] Response hash for controller
  def handle_preview_announcement(payload)
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

  private

  def find_workspace(payload)
    team_id = payload.dig("team", "id") || payload.dig("user", "team_id")
    Workspace.find_by!(platform: "slack", platform_id: team_id)
  end
end
