module Commands
  class OpenHome
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      if command.incident
        command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::Home.build(channel_id: command.channel_id))
      else
        command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::IncidentCreation.build(workspace: command.workspace))
      end
      nil
    end
  end
end
