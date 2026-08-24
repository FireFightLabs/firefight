module Commands
  class DeclareIncident
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::IncidentCreation.build(workspace: command.workspace))
      nil
    end
  end
end
