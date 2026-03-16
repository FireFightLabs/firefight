module Commands
  module Firefight
    class HomeModalHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first

        if incident
          workspace.adapter.open_home_modal(trigger_id: command.trigger_id, channel_id: command.channel_id)
        else
          workspace.adapter.open_incident_creation_modal(trigger_id: command.trigger_id)
        end
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
