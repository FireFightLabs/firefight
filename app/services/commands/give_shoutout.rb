module Commands
  class GiveShoutout
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("No active incident in this channel.") unless command.incident

      adapter = command.workspace.adapter
      adapter.open_modal(trigger_id: command.trigger_id, view: adapter.build_modal(PlatformAdapter::Modal::SHOUTOUT, command.incident))
      nil
    end
  end
end
