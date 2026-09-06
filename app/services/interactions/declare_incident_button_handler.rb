module Interactions
  # The welcome message's first step. A button click carries a trigger id
  # just like the slash command does, so it opens the same modal, marked as
  # a test incident so the first run is not counted in the metrics.
  class DeclareIncidentButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      adapter = interaction.workspace.adapter
      view = adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATION, metadata: ModalState.encode(test: true), test: true)
      adapter.open_modal(trigger_id: interaction.trigger_id, view: view)
      nil
    end
  end
end
