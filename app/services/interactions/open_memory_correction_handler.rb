module Interactions
  # Correct on a memory opens the form asking what is right instead. trigger_id expires in three seconds, so this stays sync.
  class OpenMemoryCorrectionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_MEMORY, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      post_id, memory_id = interaction.action_value.to_s.split(":", 2)
      workspace = interaction.workspace
      memory = MemoryPostService.new(workspace).correctable(post_id: post_id, memory_id: memory_id)
      return unless memory

      workspace.adapter.open_memory_correction_modal(trigger_id: interaction.trigger_id, post_id: post_id, memory: memory)
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
