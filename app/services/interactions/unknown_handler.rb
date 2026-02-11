module Interactions
  class UnknownHandler
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
