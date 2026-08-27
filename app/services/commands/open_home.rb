module Commands
  class OpenHome
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      adapter = command.workspace.adapter
      if command.incident
        adapter.open_modal(trigger_id: command.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::HOME, channel_id: command.channel_id))
      else
        adapter.open_modal(trigger_id: command.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATION))
      end
      nil
    end
  end
end
