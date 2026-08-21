module Commands
  class DeclareIncident
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

      command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::IncidentCreation.build(workspace: command.workspace))
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff new` again.")
    end
  end
end
