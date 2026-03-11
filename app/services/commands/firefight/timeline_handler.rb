module Commands
  module Firefight
    class TimelineHandler
      DEFAULT_LIMIT = 15
      PAGE_SIZE = 15
      MAX_EVENTS = 45

      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.in_channel(command.channel_id).recent.first
        return ephemeral("This command must be run from an incident channel.") unless incident

        build_response(incident, limit: DEFAULT_LIMIT)
      end

      def self.build_response(incident, limit: DEFAULT_LIMIT)
        capped_limit = [ [ limit.to_i, DEFAULT_LIMIT ].max, MAX_EVENTS ].min
        events = incident.incident_events.includes(:eventable).recent.limit(capped_limit).reverse
        return ephemeral("No timeline events found for this incident yet.") if events.empty?

        blocks = [
          {
            type: "header",
            text: { type: "plain_text", text: "#{incident.identifier} Timeline", emoji: true }
          },
          { type: "divider" }
        ]
        blocks.concat(IncidentTimelineFormatter.to_blocks(events))

        text = "Timeline for #{incident.identifier}"

        total_events = incident.incident_events.count
        if total_events > capped_limit
          blocks << { type: "actions", elements: [ load_more_button(incident.id, capped_limit) ] }
          blocks << {
            type: "context",
            elements: [
              { type: "mrkdwn", text: ":information_source: Showing latest #{capped_limit} of #{total_events} events." }
            ]
          }
        elsif total_events > DEFAULT_LIMIT
          blocks << {
            type: "context",
            elements: [
              { type: "mrkdwn", text: ":information_source: Showing latest #{total_events} events." }
            ]
          }
        end

        ephemeral(text, blocks: blocks)
      end

      def self.load_more_button(incident_id, current_limit)
        {
          type: "button",
          text: { type: "plain_text", text: "Load more", emoji: true },
          action_id: Identifiers::LOAD_MORE_TIMELINE,
          value: {
            incident_id: incident_id,
            limit: [ current_limit + PAGE_SIZE, MAX_EVENTS ].min
          }.to_json
        }
      end
      private_class_method :load_more_button

      private_class_method def self.ephemeral(text, blocks: nil)
        { response_type: "ephemeral", text: text, blocks: blocks }
      end
    end
  end
end
