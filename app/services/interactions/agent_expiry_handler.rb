module Interactions
  # When a change customers feel is undone, picked on its confirmation in a thread. Kept as soon as it is picked, so
  # Confirm runs it with that time.
  class AgentExpiryHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      conversation_id, tool_call_id, value = interaction.selected_value.to_s.split(":", 3)
      conversation = interaction.workspace.conversations.find_by(id: conversation_id)
      Conversation::Mitigations.choose!(conversation.chat, tool_call_id, value) if conversation&.chat
      nil
    end
  end
end
