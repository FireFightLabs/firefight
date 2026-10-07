module Interactions
  # Run, Dismiss or Ask again on a call Halon made in a chat that an approval rule held. The call runs as whoever asked,
  # since that is who it was approved for, and whoever pressed Run is named on it.
  class HeldCallHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      held = Chat::HeldCall.joins(:chat).where(chats: { workspace_id: workspace.id }).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      refusal = case interaction.action_id
      when Identifiers::HELD_CALL_RUN then Conversation::HeldCalls.run!(held, by: member)
      when Identifiers::HELD_CALL_DISMISS then Conversation::HeldCalls.dismiss!(held, by: member)
      else Conversation::HeldCalls.ask_again!(held, by: member)
      end
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
