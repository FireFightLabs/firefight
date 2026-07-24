module Mcp
  module Tools
    class SearchIncidents < Base
      tool_name SEARCH_INCIDENTS
      description "Search this workspace's incidents. Filter by status slug, severity slug, " \
                  "lifecycle stage (triage/active/closed/canceled), free-text query (name or " \
                  "identifier), and declared-at time range. Returns newest first. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          status: { type: "string", description: "Incident status slug, e.g. investigating" },
          severity: { type: "string", description: "Severity slug, e.g. sev1" },
          stage: { type: "string", description: "Lifecycle stage key: triage, active, closed or canceled" },
          query: { type: "string", description: "Matches incident name or identifier" },
          since: { type: "string", description: "ISO8601: only incidents declared after this time" },
          until: { type: "string", description: "ISO8601: only incidents declared before this time" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = workspace.incidents.where(deleted_at: nil).with_list_associations.recent
        scope = scope.search(args[:query]) if args[:query].present?
        scope = scope.by_severity_slugs([ args[:severity] ]) if args[:severity].present?
        scope = scope.by_lifecycle_stage_keys([ args[:stage] ]) if args[:stage].present?
        scope = scope.joins(:incident_status).where(incident_statuses: { slug: args[:status] }) if args[:status].present?
        scope = scope.where(declared_at: time_arg(args[:since])..) if time_arg(args[:since])
        scope = scope.where(declared_at: ..time_arg(args[:until])) if time_arg(args[:until])

        incidents, truncated = capped(scope, args)
        respond(
          incidents: incidents.map { |incident| summary(incident) },
          truncated: truncated
        )
      end

      def self.summary(incident)
        {
          id: incident.id,
          identifier: incident.identifier,
          name: incident.name,
          severity: incident.incident_severity.name,
          status: incident.incident_status.name,
          stage: incident.incident_status.incident_lifecycle_stage.key,
          lead: incident.lead&.display_name,
          declared_at: incident.declared_at.utc.iso8601,
          resolved_at: incident.resolved_at&.utc&.iso8601,
          summary: incident.summary
        }.compact
      end
    end
  end
end
