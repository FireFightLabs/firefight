module Commands
  module Firefight
    class ListHandler
      MAX_RESULTS = 10

      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        active_incidents = workspace.incidents
          .active
          .includes(:incident_status, :incident_severity)
          .by_severity
          .recent

        total_count = active_incidents.count
        return ephemeral("There are no active incidents right now.") if total_count.zero?

        incidents = active_incidents.limit(MAX_RESULTS)
        lines = incidents.map { |incident| format_line(incident) }

        text = [ "*Active incidents*", lines.join("\n\n") ]

        if total_count > MAX_RESULTS
          text << ""
          text << ":information_source: *Showing #{incidents.size} of #{total_count} active incidents.*"
        end

        ephemeral(text.join("\n"))
      end

      private_class_method def self.format_line(incident)
        lead = incident.lead ? "<@#{incident.lead.platform_user_id}>" : "Unassigned"
        channel = if incident.channel_id.present?
          "<##{incident.channel_id}>"
        elsif incident.is_private?
          "Private channel"
        else
          "No channel"
        end

        [
          "> *#{incident.identifier}* #{incident.name || 'Untitled Incident'}",
          "> #{incident.incident_severity.name} | #{incident.incident_status.name} | Lead: #{lead} | #{channel}"
        ].join("\n")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
