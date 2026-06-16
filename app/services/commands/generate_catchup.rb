module Commands
  class GenerateCatchup
    CATCHUP_QUESTION = <<~Q.strip
      Give me a concise catchup on this incident. Focus on the chat narrative:
      - What has been investigated and what theories the team has tested
      - Key decisions made in chat (rollbacks considered, customer comms drafted, vendor escalations)
      - Blockers and open questions ("we still don't know why X")
      - What the team is currently focused on
      Reference timeline events as supporting evidence, not as the main content.
    Q

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("AI features are not available.") unless defined?(FirefightAi)

      gate = Entitlements.check(command.workspace, Entitlements::AI)
      return Command.ephemeral(gate.message) if gate.blocked?

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
