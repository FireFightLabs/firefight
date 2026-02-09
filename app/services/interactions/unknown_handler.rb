# Fallback handler for unrecognized interaction types, callback_ids, or action_ids
module Interactions
  class UnknownHandler
    def self.execute(payload)
      Rails.logger.warn({
        event: "interactions.unknown",
        type: payload["type"],
        callback_id: payload.dig("view", "callback_id") || payload["callback_id"],
        action_id: payload.dig("actions", 0, "action_id")
      })
      nil
    end
  end
end
