module Interactions
  # Opens the declare modal from the welcome message, marked as a test
  # incident.
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
