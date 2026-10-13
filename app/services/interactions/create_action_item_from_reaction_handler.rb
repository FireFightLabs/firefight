module Interactions
  # Carries where the source message is, so the description starts from it, and the prompt's handle so the submit
  # handler can take the prompt down. The form opens on the trigger and Slack is answered at once, and the message is
  # read in the background (ActionItemFormFillInJob).
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
        channel_id: metadata["channel_id"],
        source_message_id: metadata["message_id"],
        source_message_text: metadata["source_message_text"],
        source_message_link: metadata["source_message_link"],
        prompt_handle: interaction.prompt_handle
      )

      kind = KINDS.fetch(interaction.action_id)
      opened = workspace.adapter.open_action_item_modal(
        kind: kind,
        trigger_id: interaction.trigger_id,
        incident: incident,
        private_metadata: private_metadata
      )
      if opened[:view_id] && metadata["message_id"] && metadata["channel_id"]
        ActionItemFormFillInJob.perform_later(workspace.id, incident.id, kind.to_s, opened[:view_id], private_metadata)
      end

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
