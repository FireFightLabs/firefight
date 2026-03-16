module Commands
  module Firefight
    class ShoutoutHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first
        return ephemeral("No active incident in this channel.") unless incident

        adapter = WorkspaceAdapter.for(workspace)
        adapter.open_shoutout_modal(trigger_id: command.trigger_id, incident: incident)
        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff shoutout` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
