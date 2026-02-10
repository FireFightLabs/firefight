module Interactions
  class NoopHandler
    def self.execute(_interaction)
      { response_action: "clear" }
    end
  end
end
