module Interactions
  # The "Add action" and "Add follow-up" buttons on the action list modals.
  # The action_id names the kind.
  class OpenActionItemFormHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    KINDS = {
      Identifiers::ADD_NEW_ACTION => :action,
      Identifiers::ADD_NEW_FOLLOWUP => :followup
    }.freeze

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      workspace.adapter.open_action_item_modal(
        kind: KINDS.fetch(interaction.action_id), trigger_id: interaction.trigger_id, incident: incident, push: true
      )
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
