module Commands
  class ListHandler
    MAX_RESULTS = 10

    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace

      build_response(command.workspace)
    end

    def self.build_response(workspace)
      active_incidents = workspace.incidents
        .active
        .includes(:incident_status, :incident_severity)
        .by_severity
        .recent

      total_count = active_incidents.count
      return Command.ephemeral("There are no active incidents right now.") if total_count.zero?

      incidents = active_incidents.limit(MAX_RESULTS)
      lines = incidents.map { |incident| workspace.adapter.format_incident_list_line(incident) }

      text = [ "*Active incidents*", lines.join("\n\n") ]

      if total_count > MAX_RESULTS
        text << ""
        text << ":information_source: *Showing #{incidents.size} of #{total_count} active incidents.*"
      end

      Command.ephemeral(text.join("\n"))
    end
  end
end
