module Interactions
  # The Declare incident button on an answer that says users are hurt now. The run rides in the modal's state, so the
  # incident declared from it carries the run.
  class DeclareFromInvestigationHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      adapter = interaction.workspace.adapter
      view = adapter.build_modal(
        PlatformAdapter::Modal::INCIDENT_CREATION, metadata: ModalState.encode(investigation_id: interaction.action_value)
      )
      adapter.open_modal(trigger_id: interaction.trigger_id, view: view)
      nil
    end
  end
end
