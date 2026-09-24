module Commands
  class StartInvestigation
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(command)
      workspace = command.workspace
      return Command.ephemeral("This command must be run from an incident channel.") unless command.incident

      refusal = Investigation.start_refusal(command.incident)
      return Command.ephemeral(refusal) if refusal

      started = InvestigationService.new(workspace).start(
        command.incident,
        trigger_source: Investigation::TRIGGER_COMMAND,
        triggered_by: workspace.workspace_memberships.find_by!(platform_user_id: command.user_id),
        brief: brief(command)
      )
      return nil if started

      Command.ephemeral(Investigation.already_running_message(command.incident))
    end

    # Whatever follows the subcommand is what the person already knows, such as "checkout 500s since 2pm".
    def self.brief(command)
      Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => command.args.drop(1).join(" ") }, source: Investigation::Brief::SOURCE_COMMAND)
    end
    private_class_method :brief
  end
end
