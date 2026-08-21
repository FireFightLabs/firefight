module Commands
  class AssignLead
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::Lead.build(command.incident))
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff lead` again.")
    end
  end
end
