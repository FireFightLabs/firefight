module Commands
  module Firefight
    class ReopenHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.closed.in_channel(command.channel_id).first
        return ephemeral("This command must be run from a closed incident channel.") unless incident

        ReopenModalOpener.open(
          workspace: workspace,
          incident: incident,
          trigger_id: command.trigger_id,
          user_id: command.user_id
        )

        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff reopen` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
