module Commands
  class CatchupHandler
    CATCHUP_QUESTION = "Give me a concise catchup on this incident. Include: what happened, current status, who's involved, key timeline events, and next steps."

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("AI features are not available.") unless defined?(FirefightAi)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      FirefightAi::IncidentResponseJob.perform_later(
        command.incident.id,
        command.channel_id,
        nil,
        CATCHUP_QUESTION
      )
      Command.ephemeral("Generating catchup for #{command.incident.identifier}...")
    end
  end
end
