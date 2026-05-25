module Commands
  class ShowTimeline
    DEFAULT_LIMIT = 15

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

      incident = command.workspace.incidents.in_channel(command.channel_id).recent.first
      return Command.ephemeral("This command must be run from an incident channel.") unless incident

      command.workspace.adapter.open_timeline_modal(trigger_id: command.trigger_id, incident: incident, limit: DEFAULT_LIMIT)
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff timeline` again.")
    end
  end
end
