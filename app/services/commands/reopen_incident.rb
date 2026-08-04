module Commands
  class ReopenIncident
    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

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
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff reopen` again.")
    end
  end
end
