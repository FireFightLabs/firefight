module Commands
  class EscalateIncident
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      ModalOpener.open(
        :escalate,
        workspace: command.workspace,
        incident: command.incident,
        trigger_id: command.trigger_id,
        user_id: command.user_id
      )

      nil
    end
  end
end
