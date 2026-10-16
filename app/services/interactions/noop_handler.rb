module Interactions
  class NoopHandler
    extend HandlerAuthorization
    authorizes_nothing

    def self.execute(interaction)
      interaction.workspace.adapter.modal_close_response
    end
  end
end
