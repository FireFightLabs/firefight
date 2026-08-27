module Mcp
  module Tools
    class GetIncident < Base
      TIMELINE_LIMIT = 50

      tool_name GET_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS
      description "Fetch one incident in full by id or identifier (e.g. INC-42): details, " \
                  "timeline events, postmortem status, and the alerts attached to it. " \
                  "Docs: #{Docs::INCIDENTS}"
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

        events = incident.incident_events.undismissed.order(created_at: :desc).limit(TIMELINE_LIMIT + 1).to_a
        respond(
          **SearchIncidents.summary(incident),
          channel_id: incident.channel_id,
          timeline: events.first(TIMELINE_LIMIT).reverse.map { |event| timeline_entry(event) },
          timeline_truncated: events.size > TIMELINE_LIMIT,
          postmortem: postmortem(incident),
          alerts: incident.alerts.map { |alert| SearchAlerts.summary(alert) },
          roles: roles(incident),
          action_items: action_items(incident),
          runbooks: runbooks(incident)
        )
      end

      # Every role the workspace configured, held or not, so an agent can see
      # what it may assign without a second call.
      def self.roles(incident)
        holders = incident.incident_role_assignments.includes(:workspace_membership).index_by(&:incident_role_id)

        incident.workspace.incident_roles.active.ordered.map do |role|
          {
            slug: role.slug,
            name: role.name,
            description: role.description,
            held_by: holders[role.id]&.workspace_membership&.display_name
          }.compact
        end
      end

      # The work, with the ids the write tools take. Without these an agent
      # can see that an item exists and has no way to name it.
      def self.action_items(incident)
        incident.incident_actions.active.order(:created_at).map do |action|
          {
            id: action.id,
            kind: action.action_type,
            description: action.description,
            status: action.status,
            assignee: action.assignee&.actor_display_name
          }.compact
        end
      end

      def self.runbooks(incident)
        incident.incident_runbooks.includes(runbook: :runbook_steps).map do |attachment|
          actions = attachment.actions_by_step
          {
            id: attachment.id,
            name: attachment.runbook.name,
            steps: attachment.runbook.runbook_steps.sort_by(&:position).map do |step|
              action = actions[step.id]
              {
                id: step.id,
                title: step.title,
                claimed_by: action&.assignee&.actor_display_name,
                done: action&.done? || false
              }.compact
            end
          }
        end
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
          kind: event.metadata.to_h["kind"],
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
