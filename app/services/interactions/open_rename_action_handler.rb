module Interactions
  # Rename on an item's message opens the form holding its title. trigger_id expires in three seconds, so this stays sync.
  class OpenRenameActionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      action = IncidentAction.in_workspace(workspace).active.find(interaction.action_value)

      # From the item list modal the form goes on top of it rather than replacing it.
      workspace.adapter.open_rename_action_modal(trigger_id: interaction.trigger_id, action: action, push: interaction.view_id.present?)
      nil
    rescue ActiveRecord::RecordNotFound, AdapterError::TriggerExpired
      nil
    end
  end
end
