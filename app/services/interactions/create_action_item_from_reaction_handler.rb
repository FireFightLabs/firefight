module Interactions
  # The message shortcut behind the :boom: and :arrow_forward: reactions.
  # Opens the matching form with the source message carried along so the
  # description starts from it.
  class CreateActionItemFromReactionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    KINDS = {
      Identifiers::CREATE_ACTION_FROM_REACTION => :action,
      Identifiers::CREATE_FOLLOWUP_FROM_REACTION => :followup
    }.freeze

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = JSON.parse(interaction.action_value)
      incident = workspace.incidents.find(metadata["incident_id"])

      private_metadata = ModalState.encode(
        incident_id: incident.id,
        source_message_text: metadata["source_message_text"],
        source_message_link: metadata["source_message_link"]
      )

      workspace.adapter.open_action_item_modal(
        kind: KINDS.fetch(interaction.action_id),
        trigger_id: interaction.trigger_id,
        incident: incident,
        private_metadata: private_metadata
      )

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
