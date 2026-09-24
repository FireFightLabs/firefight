module Commands
  class StartInvestigation
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    # In an incident's channel it investigates the incident. Anywhere else it investigates what the person says is
    # wrong and answers in that channel, so a question does not wait for someone to declare an incident.
    def self.execute(command)
      workspace = command.workspace
      incident = command.incident
      brief = brief(command)
      return Command.ephemeral(Investigation::NEEDS_A_QUESTION) if incident.nil? && brief.empty?

      refusal = Investigation.start_refusal(workspace, incident)
      return Command.ephemeral(refusal) if refusal

      started = InvestigationService.new(workspace).start(
        incident,
        trigger_source: Investigation::TRIGGER_COMMAND,
        triggered_by: workspace.workspace_memberships.find_by!(platform_user_id: command.user_id),
        brief: brief,
        channel_id: (command.channel_id unless incident)
      )
      return nil if started

      Command.ephemeral(Investigation.already_running_message(incident))
    end

    # Whatever follows the subcommand is what the person already knows, such as "checkout 500s since 2pm".
    def self.brief(command)
      Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => command.args.drop(1).join(" ") }, source: Investigation::Brief::SOURCE_COMMAND)
    end
    private_class_method :brief
  end
end
