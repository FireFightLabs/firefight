module Interactions
  # The owner's answer, in their direct messages, to Halon stopping something they started. Only they can answer.
  class OwnerAskHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      ask = Chat::OwnerAsk.where(workspace_id: workspace.id).find_by(id: interaction.action_value)
      return nil unless ask

      member = workspace.workspace_memberships.find_by(platform_user_id: interaction.user_id)
      refusal = Conversation::OwnerAsks.answer!(ask, agreed: interaction.action_id == Identifiers::OWNER_AGREE, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    end
  end
end
