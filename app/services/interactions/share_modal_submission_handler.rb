# Handles the share incidents channel modal submission
# Posts share messages to selected conversations
module Interactions
  class ShareModalSubmissionHandler
    extend WorkspaceFinding

    def self.execute(payload)
      workspace = find_workspace(payload)
      user_id = payload.dig("user", "id")

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
  end
end
