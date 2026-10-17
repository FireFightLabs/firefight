module Interactions
  class ShareModalSubmissionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter

      selected_conversations = adapter.submitted_value(values: interaction.values, block_id: Identifiers::SHARE_TARGET_BLOCK, input_id: Identifiers::SHARE_TARGET_SELECT, kind: PlatformAdapter::Input::CONVERSATIONS) || []

      if selected_conversations.empty?
        Rails.logger.warn({
          event: "interactions.share_no_targets",
          message: "User tried to share without selecting targets",
          workspace_id: workspace.id,
          user_id: interaction.user_id
        })

        return adapter.modal_errors_response({ Identifiers::SHARE_TARGET_BLOCK => "Please select at least one channel or person" })
      end

      result = adapter.post_share_messages(
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

      adapter.modal_close_response
    end
  end
end
