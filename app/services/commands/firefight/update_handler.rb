module Commands
  module Firefight
    class UpdateHandler
      def self.execute(command)
        return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
        return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

        IncidentUpdateModalOpener.open(
          workspace: command.workspace,
          incident: command.incident,
          trigger_id: command.trigger_id,
          user_id: command.user_id
        )
        nil
      rescue AdapterError::TriggerExpired
        Command.ephemeral("This command has expired. Please try `/ff update` again.")
      end
    end
  end
end
