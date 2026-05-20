module Commands
  class HomeModalHandler
    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

      if command.incident
        command.workspace.adapter.open_home_modal(trigger_id: command.trigger_id, channel_id: command.channel_id)
      else
        command.workspace.adapter.open_incident_creation_modal(trigger_id: command.trigger_id)
      end
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff` again.")
    end
  end
end
