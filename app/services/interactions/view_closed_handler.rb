module Interactions
  class ViewClosedHandler
    extend HandlerAuthorization
    authorizes_nothing
    # Any modal opened with a placeholder in the channel carries its id in the
    # private metadata, so that is what decides whether there is something to
    # clean up. Listing callback_ids here instead meant a new modal was one
    # forgotten line away from leaving "is canceling the incident..." behind
    # forever, which is exactly what happened to Cancel.
    def self.execute(interaction)
      metadata = interaction.metadata
      return nil if metadata.temp_message_ts.blank? || metadata.channel_id.blank?

      Interactions::ModalCleanup.delete_temp_message(interaction.workspace, metadata)
      nil
    end
  end
end
