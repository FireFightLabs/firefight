module Commands
  module Firefight
    class FollowupsHandler
      def self.execute(command)
        return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
        return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

        command.workspace.adapter.open_followups_list_modal(trigger_id: command.trigger_id, incident: command.incident)
        nil
      rescue AdapterError::TriggerExpired
        Command.ephemeral("This command has expired. Please try `/ff followups` again.")
      end
    end
  end
end
