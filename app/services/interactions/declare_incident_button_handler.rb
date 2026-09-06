module Interactions
  # The welcome message's first step. A button click carries a trigger id
  # just like the slash command does, so it opens the same modal.
  class DeclareIncidentButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      adapter = interaction.workspace.adapter
      adapter.open_modal(trigger_id: interaction.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATION))
      nil
    end
  end
end
