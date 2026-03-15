module Commands
  module Firefight
    class StatusHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first
        return ephemeral("This command must be run from an active incident channel.") unless incident

        IncidentUpdateModalOpener.open(
          workspace: workspace,
          incident: incident,
          trigger_id: command.trigger_id,
          user_id: command.user_id
        )
        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff status` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
