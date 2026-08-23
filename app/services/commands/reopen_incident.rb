module Commands
  class ReopenIncident
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      incident = command.workspace.incidents.terminal.in_channel(command.channel_id).first
      return Command.ephemeral("This command must be run from a resolved or canceled incident channel.") unless incident

      ModalOpener.open(
        :reopen,
        workspace: command.workspace,
        incident: incident,
        trigger_id: command.trigger_id,
        user_id: command.user_id
      )

      nil
    end
  end
end
