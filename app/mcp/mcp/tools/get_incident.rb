module Mcp
  module Tools
    class GetIncident < Base
      TIMELINE_LIMIT = 50

      tool_name GET_INCIDENT
      description "Fetch one incident in full by id or identifier (e.g. INC-42): details, " \
                  "timeline events, postmortem status, and the alerts attached to it."
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" }
        },
        required: [ "incident" ]
      )

      def self.perform(workspace:, args:)
        reference = args[:incident].to_s
        scope = workspace.incidents.where(deleted_at: nil)
        incident = find_by_reference(scope, reference)
        raise ActiveRecord::RecordNotFound unless incident

        events = incident.incident_events.order(created_at: :desc).limit(TIMELINE_LIMIT + 1).to_a
        respond(
          **SearchIncidents.summary(incident),
          channel_id: incident.channel_id,
          timeline: events.first(TIMELINE_LIMIT).reverse.map { |event| timeline_entry(event) },
          timeline_truncated: events.size > TIMELINE_LIMIT,
          postmortem: postmortem(incident),
          alerts: incident.alerts.map { |alert| SearchAlerts.summary(alert) }
        )
      end

      def self.find_by_reference(scope, reference)
        if reference.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
          scope.find_by(id: reference)
        else
          scope.find_by(identifier: reference)
        end
      end

      def self.timeline_entry(event)
        {
          event: event.event_type,
          description: event.description,
          at: event.created_at.utc.iso8601,
          metadata: event.metadata.presence
        }.compact
      end

      def self.postmortem(incident)
        postmortem = incident.postmortem
        return nil unless postmortem

        { status: postmortem.status, updated_at: postmortem.updated_at.utc.iso8601 }
      end
    end
  end
end
