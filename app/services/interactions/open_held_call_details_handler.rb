module Interactions
  # Details on a held call opens the call as it was given, which its message keeps off it. trigger_id expires in three
  # seconds, so this stays sync.
  class OpenHeldCallDetailsHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS

    def self.execute(interaction)
      workspace = interaction.workspace
      held = Chat::HeldCall.joins(:chat).where(chats: { workspace_id: workspace.id }).find_by(id: interaction.action_value)
      return unless held

      workspace.adapter.open_held_call_details(trigger_id: interaction.trigger_id, held_call: Conversation::HeldCalls.shown(held))
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
