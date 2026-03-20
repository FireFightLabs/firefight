module Commands
  module Firefight
    class PostmortemHandler
      def self.execute(command)
        return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

        incident = command.workspace.incidents.closed.in_channel(command.channel_id).first
        return Command.ephemeral("This command must be run from a closed incident channel.") unless incident
        return Command.ephemeral("A postmortem has already been generated for #{incident.identifier}.") if incident.postmortem.present?

        member = command.workspace.workspace_memberships.find_by(platform_user_id: command.user_id)
        return Command.ephemeral("Could not identify your workspace membership.") unless member

        PostmortemGenerationJob.perform_later(incident.id, member.id)
        Command.ephemeral("Generating postmortem for #{incident.identifier}... This may take a minute.")
      end
    end
  end
end
