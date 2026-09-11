module Commands
  class StartInvestigation
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(command)
      workspace = command.workspace
      unavailable = Investigation.unavailable_reason(workspace)
      return Command.ephemeral(unavailable) if unavailable
      return Command.ephemeral("This command must be run from an incident channel.") unless command.incident

      blocked = command.incident.investigation_blocked_reason
      return Command.ephemeral(blocked) if blocked

      service = InvestigationService.new(workspace)
      running = service.live_for(command.incident)
      return Command.ephemeral(already_running_message(command.incident)) if running

      service.start(
        command.incident,
        trigger_source: Investigation::TRIGGER_COMMAND,
        triggered_by: workspace.workspace_memberships.find_by(platform_user_id: command.user_id)
      )
      nil
    end

    private_class_method def self.already_running_message(incident)
      "Already investigating #{incident.identifier}, I will post here when I have something."
    end
  end
end
