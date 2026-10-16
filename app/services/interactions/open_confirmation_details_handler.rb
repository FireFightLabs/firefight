module Interactions
  # Details on a request to approve a change opens everything its card keeps off it. trigger_id expires in three seconds,
  # so this stays sync. Anyone who can read the thread saw all of it on the card before, so reading is enough.
  class OpenConfirmationDetailsHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS

    def self.execute(interaction)
      conversation_id, tool_call_id = interaction.action_value.to_s.split(":", 2)
      workspace = interaction.workspace
      chat = workspace.conversations.find_by(id: conversation_id)&.chat
      tool_call = chat&.tool_calls&.find_by(tool_call_id: tool_call_id)
      return unless tool_call

      workspace.adapter.open_agent_confirmation_details(trigger_id: interaction.trigger_id, confirmation: Chat::Tools.confirmation(tool_call))
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
