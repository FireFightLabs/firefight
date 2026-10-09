module Interactions
  # Stop on a line a watch said in Slack. Whoever may stop the watch in words may press it: the asker, and anyone in
  # the channel for a watch started there. Anyone else, or a press after the watch ended, is told why.
  class StopWatchHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      update = Chat::Watch::Update.joins(:watch).where(chat_watches: { workspace_id: workspace.id }).find_by(id: interaction.action_value)
      return nil unless update

      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)
      refusal = Conversation::Watches.stop_pressed!(update, by: member, channel_id: interaction.channel_id, message_id: interaction.message_id)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    end
  end
end
