module Commands
  class GiveShoutout
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("No active incident in this channel.") unless command.incident

      command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::Shoutout.build(command.incident))
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff shoutout` again.")
    end
  end
end
