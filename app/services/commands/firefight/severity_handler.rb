module Commands
  module Firefight
    class SeverityHandler
      def self.execute(command)
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
        return ephemeral("This command must be run from an active incident channel.") unless command.incident

        IncidentUpdateModalOpener.open(
          workspace: command.workspace,
          incident: command.incident,
          trigger_id: command.trigger_id,
          user_id: command.user_id
        )
        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff severity` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
