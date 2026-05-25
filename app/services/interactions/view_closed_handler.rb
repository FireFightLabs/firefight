module Interactions
  class ViewClosedHandler
    def self.execute(interaction)
      return unless [ Identifiers::UPDATE_SUMMARY_MODAL, Identifiers::INCIDENT_UPDATE_MODAL, Identifiers::CLOSE_INCIDENT_MODAL, Identifiers::REOPEN_INCIDENT_MODAL ].include?(interaction.callback_id)

      delete_temp_message(interaction)
      nil
    end

    def self.delete_temp_message(interaction)
      metadata = JSON.parse(interaction.private_metadata)
      return unless metadata["temp_message_ts"] && metadata["channel_id"]

      workspace = interaction.workspace
      workspace.adapter.delete_message(channel_id: metadata["channel_id"], message_id: metadata["temp_message_ts"])
    rescue JSON::ParserError, AdapterError => e
      Rails.logger.warn({ event: "interactions.view_closed.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
