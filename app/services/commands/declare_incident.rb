module Commands
  class DeclareIncident
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      adapter = command.workspace.adapter
      adapter.open_modal(trigger_id: command.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATION))
      nil
    end
  end
end
