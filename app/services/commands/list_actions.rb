module Commands
  class ListActions
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      adapter = command.workspace.adapter
      adapter.open_modal(trigger_id: command.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::ACTION_ITEMS_LIST, command.incident, kind: :action))
      nil
    end
  end
end
