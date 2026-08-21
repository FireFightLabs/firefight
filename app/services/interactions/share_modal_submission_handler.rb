module Interactions
  class ShareModalSubmissionHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace

      selected_conversations = interaction.values.dig(
        "share_target_block",
        "share_target_select",
        "selected_conversations"
      ) || []

      if selected_conversations.empty?
        Rails.logger.warn({
          event: "interactions.share_no_targets",
          message: "User tried to share without selecting targets",
          workspace_id: workspace.id,
          user_id: interaction.user_id
        })

        return {
          response_action: "errors",
          errors: { share_target_block: "Please select at least one channel or person" }
        }
      end

      result = workspace.adapter.post_share_messages(
        user_id: interaction.user_id,
        channel_id: workspace.incidents_channel_id,
        target_conversations: selected_conversations
      )

      Rails.logger.info({
        event: "interactions.channel_shared",
        message: "Shared incidents channel",
        workspace_id: workspace.id,
        user_id: interaction.user_id,
        target_count: result[:shared_count],
        targets: selected_conversations
      })

      { response_action: "clear" }
    end
  end
end
