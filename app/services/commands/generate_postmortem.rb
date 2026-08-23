module Commands
  class GeneratePostmortem
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

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
      return Command.ephemeral("A postmortem has already been generated for #{incident.identifier}.") if incident.postmortem.present?

      member = command.workspace.workspace_memberships.find_by(platform_user_id: command.user_id)
      return Command.ephemeral("Could not identify your workspace membership.") unless member

      FirefightAi::PostmortemGenerationJob.perform_later(incident.id, member.id)
      Command.ephemeral("Generating postmortem for #{incident.identifier}... This may take a minute.")
    end
  end
end
