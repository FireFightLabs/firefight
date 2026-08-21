module Interactions
  class NoopHandler
    extend HandlerAuthorization
    authorizes_nothing

    def self.execute(_interaction)
      { response_action: "clear" }
    end
  end
end
