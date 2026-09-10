module Interactions
  class ViewClosedHandler
    extend HandlerAuthorization
    authorizes_nothing
    # The metadata decides whether there is a placeholder to clean up. Listing
    # callback_ids here instead once left "is canceling the incident..." behind forever.
    def self.execute(interaction)
      metadata = interaction.metadata
      return nil if metadata.temp_message_ts.blank? || metadata.channel_id.blank?

      Interactions::ModalCleanup.delete_temp_message(interaction.workspace, metadata)
      nil
    end
  end
end
