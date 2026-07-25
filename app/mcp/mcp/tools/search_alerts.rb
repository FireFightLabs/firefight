module Mcp
  module Tools
    class SearchAlerts < Base
      tool_name SEARCH_ALERTS
      authorize_as ApiKey::RESOURCE_ALERTS
      description "Search this workspace's ingested alerts: what fired, how each routed " \
                  "(routed/unmatched/pending/failed), which rule matched, and the incident it " \
                  "attached to. Newest first. Docs: #{Docs::ALERTS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          source: { type: "string", description: "Alert source name to filter by" },
          routing_state: { type: "string", description: "pending, routed, unmatched or failed" },
          status: { type: "string", description: "firing or resolved" },
          since: { type: "string", description: "ISO8601: only alerts last seen after this time" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = workspace.alerts
          .includes(:alert_source, :incident, matched_policy_rule: :policy)
          .order(last_seen_at: :desc)
        if args[:source].present?
          source = workspace.alert_sources.find_by(name: args[:source])
          raise ActiveRecord::RecordNotFound unless source

          scope = scope.where(alert_source: source)
        end
        scope = scope.where(routing_state: args[:routing_state]) if args[:routing_state].present?
        scope = scope.where(status: args[:status]) if args[:status].present?
        scope = scope.where(last_seen_at: time_arg(args[:since])..) if time_arg(args[:since])

        alerts, truncated = capped(scope, args)
        respond(alerts: alerts.map { |alert| summary(alert) }, truncated: truncated)
      end

      def self.summary(alert)
        {
          id: alert.id,
          title: alert.title,
          source: alert.alert_source.name,
          status: alert.status,
          routing_state: alert.routing_state,
          matched_rule_priority: alert.matched_policy_rule&.priority,
          incident_identifier: alert.incident&.identifier,
          fired_count: alert.event_count,
          first_seen_at: alert.received_at.utc.iso8601,
          last_seen_at: alert.last_seen_at.utc.iso8601
        }.compact
      end
    end
  end
end
