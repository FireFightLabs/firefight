module Commands
  class ListFollowups
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::ActionItemsList.build(command.incident, kind: :followup))
      nil
    end
  end
end
