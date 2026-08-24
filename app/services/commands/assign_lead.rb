module Commands
  class AssignLead
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::Lead.build(command.incident))
      nil
    end
  end
end
