module Interactions
  class ViewClosedHandler
    # Any modal opened with a placeholder in the channel carries its id in the
    # private metadata, so that is what decides whether there is something to
    # clean up. Listing callback_ids here instead meant a new modal was one
    # forgotten line away from leaving "is canceling the incident..." behind
    # forever, which is exactly what happened to Cancel.
    def self.execute(interaction)
      delete_temp_message(interaction)
      nil
    end

    def self.delete_temp_message(interaction)
      return if interaction.private_metadata.blank?

      metadata = JSON.parse(interaction.private_metadata)
      return unless metadata.is_a?(Hash) && metadata["temp_message_ts"] && metadata["channel_id"]

      workspace = interaction.workspace
      workspace.adapter.delete_message(channel_id: metadata["channel_id"], message_id: metadata["temp_message_ts"])
    rescue JSON::ParserError, AdapterError => e
      Rails.logger.warn({ event: "interactions.view_closed.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
