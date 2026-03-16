module Commands
  module Firefight
    class TimelineHandler
      DEFAULT_LIMIT = 15

      def self.execute(command)
        return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

        incident = command.workspace.incidents.in_channel(command.channel_id).recent.first
        return Command.ephemeral("This command must be run from an incident channel.") unless incident

        response = command.workspace.adapter.build_timeline_response(incident, limit: DEFAULT_LIMIT)
        return Command.ephemeral("No timeline events found for this incident yet.") unless response

        Command.ephemeral(response[:text], blocks: response[:blocks])
      end
    end
  end
end
