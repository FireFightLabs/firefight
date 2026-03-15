module Commands
  module Firefight
    class FollowupsHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first
        return ephemeral("This command must be run from an active incident channel.") unless incident

        adapter = WorkspaceAdapter.for(workspace)
        adapter.open_followups_list_modal(trigger_id: command.trigger_id, incident: incident)
        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff followups` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
