module Commands
  class ShowTimeline
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

      incident = command.workspace.incidents.in_channel(command.channel_id).recent.first
      return Command.ephemeral("This command must be run from an incident channel.") unless incident

      command.workspace.adapter.open_timeline_modal(trigger_id: command.trigger_id, incident: incident)
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff timeline` again.")
    end
  end
end
