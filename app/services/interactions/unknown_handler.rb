module Interactions
  class UnknownHandler
    extend HandlerAuthorization
    authorizes_nothing

    def self.execute(interaction)
      Rails.logger.warn({
        event: "interactions.unknown",
        type: interaction.type,
        callback_id: interaction.callback_id,
        action_id: interaction.action_id
      })
      nil
    end
  end
end
