module Commands
  class GeneratePostmortem
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(command)
      return Command.ephemeral("AI features are not available.") unless defined?(FirefightAi)

      gate = Entitlements.check(command.workspace, Entitlements::AI)
      return Command.ephemeral(gate.message) if gate.blocked?

      incident = command.workspace.incidents.closed.in_channel(command.channel_id).first
      unless incident
        # A canceled incident is finished, so "must be run from a closed
        # channel" reads like a mistake. Name the real reason instead.
        canceled = command.workspace.incidents.canceled.in_channel(command.channel_id).first
        return Command.ephemeral("#{canceled.identifier} was canceled, so it has no postmortem to write.") if canceled

        return Command.ephemeral("This command must be run from a resolved incident channel.")
      end
      postmortem = incident.postmortem
      if postmortem && !postmortem.generating? && !postmortem.generation_failed?
        return Command.ephemeral("A postmortem has already been generated for #{incident.identifier}.")
      end

      member = command.workspace.workspace_memberships.find_by(platform_user_id: command.user_id)
      return Command.ephemeral("Could not identify your workspace membership.") unless member

      # The same placeholder the dashboard creates, so a second request from
      # either surface while one runs is a no-op rather than a second job.
      if Postmortem.start_generation!(incident, by: member)
        PostmortemGenerationJob.perform_later(incident.id, member.id)
      end
      Command.ephemeral("Generating postmortem for #{incident.identifier}... This may take a minute.")
    end
  end
end
