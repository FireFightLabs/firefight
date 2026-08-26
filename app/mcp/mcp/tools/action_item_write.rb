module Mcp
  module Tools
    # What the action-item tools share: finding the item, and saying what it
    # looks like afterwards.
    module ActionItemWrite
      def self.find!(workspace, incident_reference, action_id)
        incident = IncidentWrite.find!(workspace, incident_reference)
        [ incident, incident.incident_actions.active.find(action_id.to_s) ]
      end

      def self.summary(action)
        {
          id: action.id,
          incident: action.incident.identifier,
          kind: action.action_type,
          description: action.description,
          status: action.status,
          assignee: action.assignee&.actor_display_name
        }.compact
      end
    end
  end
end
