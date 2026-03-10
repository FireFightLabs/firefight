module Commands
  module Firefight
    class TimelineHandler
      MAX_EVENTS = 30

      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.in_channel(command.channel_id).recent.first
        return ephemeral("This command must be run from an incident channel.") unless incident

        events = incident.incident_events.includes(:eventable).recent.limit(MAX_EVENTS).reverse
        return ephemeral("No timeline events found for this incident yet.") if events.empty?

        lines = events.map { |event| IncidentTimelineFormatter.to_text(event) }

        text = [
          "*Timeline for #{incident.identifier}*",
          lines.join("\n")
        ]

        if incident.incident_events.count > MAX_EVENTS
          text << ""
          text << ":information_source: *Showing latest #{MAX_EVENTS} events.*"
        end

        ephemeral(text.join("\n"))
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
