module Commands
  module Firefight
    class TimelineHandler
      DEFAULT_LIMIT = 15

      def self.execute(command)
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

        incident = command.workspace.incidents.in_channel(command.channel_id).recent.first
        return ephemeral("This command must be run from an incident channel.") unless incident

        response = command.workspace.adapter.build_timeline_response(incident, limit: DEFAULT_LIMIT)
        return ephemeral("No timeline events found for this incident yet.") unless response

        ephemeral(response[:text], blocks: response[:blocks])
      end

      private_class_method def self.ephemeral(text, blocks: nil)
        { response_type: Command::EPHEMERAL, text: text, blocks: blocks }
      end
    end
  end
end
