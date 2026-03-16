module Commands
  module Firefight
    class LinkHandler
      def self.execute(command)
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
        return ephemeral("This command can only be used in an active incident channel.") unless command.incident

        command.workspace.adapter.open_link_incident_modal(trigger_id: command.trigger_id, incident: command.incident)

        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff link` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
