module Commands
  class StartInvestigation
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(command)
      workspace = command.workspace
      return Command.ephemeral("This command must be run from an incident channel.") unless command.incident

      refusal = Investigation.unavailable_reason(workspace) || command.incident.investigation_blocked_reason
      return Command.ephemeral(refusal) if refusal

      started = InvestigationService.new(workspace).start(
        command.incident,
        trigger_source: Investigation::TRIGGER_COMMAND,
        triggered_by: workspace.workspace_memberships.find_by!(platform_user_id: command.user_id)
      )
      return nil if started

      Command.ephemeral(Investigation.already_running_message(command.incident))
    end
  end
end
