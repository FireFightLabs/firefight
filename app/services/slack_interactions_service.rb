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

  # Handle share incidents channel button click
  #
  # @param payload [Hash] Slack interaction payload
  # @return [Hash] Response hash for controller
  def handle_share_channel(payload)
    workspace = find_workspace(payload)
    user_id = payload.dig("user", "id")
    trigger_id = payload["trigger_id"]

    adapter = Slack::WorkspaceAdapter.new(workspace)
    adapter.open_share_modal(
      trigger_id: trigger_id,
      user_id: user_id,
      channel_id: workspace.incidents_channel_id
    )

    Rails.logger.info({
      event: "interactions.share_modal_opened",
      message: "Opened share channel modal",
      workspace_id: workspace.id,
      user_id: user_id
    })

    { response_action: "clear" }
  rescue Slack::Client::TriggerExpiredError
    Rails.logger.warn({
      event: "interactions.trigger_expired",
      message: "Trigger ID expired when opening share modal",
      workspace_id: workspace.id,
      user_id: user_id
    })

    {
      response_action: "errors",
      errors: { base: "This interaction has expired. Please try again." }
    }
  end

  # Handle share modal submission
  #
  # @param payload [Hash] Slack interaction payload
  # @return [Hash] Response hash for controller
  def handle_share_modal_submission(payload)
    workspace = find_workspace(payload)
    user_id = payload.dig("user", "id")

    # Extract selected channels/users from modal
    values = payload.dig("view", "state", "values")
    selected_conversations = values.dig(
      "share_target_block",
      "share_target_select",
      "selected_conversations"
    ) || []

    if selected_conversations.empty?
      Rails.logger.warn({
        event: "interactions.share_no_targets",
        message: "User tried to share without selecting targets",
        workspace_id: workspace.id,
        user_id: user_id
      })

      return {
        response_action: "errors",
        errors: { share_target_block: "Please select at least one channel or person" }
      }
    end

    # Send share message to each selected target
    adapter = Slack::WorkspaceAdapter.new(workspace)
    result = adapter.post_share_messages(
      user_id: user_id,
      channel_id: workspace.incidents_channel_id,
      target_conversations: selected_conversations
    )

    Rails.logger.info({
      event: "interactions.channel_shared",
      message: "Shared incidents channel",
      workspace_id: workspace.id,
      user_id: user_id,
      target_count: result[:shared_count],
      targets: selected_conversations
    })

    { response_action: "clear" }
  end

  private

  def find_workspace(payload)
    team_id = payload.dig("team", "id") || payload.dig("user", "team_id")
    Workspace.find_by!(platform: "slack", platform_id: team_id)
  end
end
