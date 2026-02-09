# Handles interactions that require no action (e.g., disabled preview buttons)
# Returns a "clear" response to dismiss any loading state
module Interactions
  class NoopHandler
    def self.execute(_payload)
      { response_action: "clear" }
    end
  end
end
