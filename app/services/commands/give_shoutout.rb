module Commands
  class GiveShoutout
    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("No active incident in this channel.") unless command.incident

      command.workspace.adapter.open_shoutout_modal(trigger_id: command.trigger_id, incident: command.incident)
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff shoutout` again.")
    end
  end
end
