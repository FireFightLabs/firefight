module Mcp
  module Tools
    module ActionItemWrite
      def self.find!(workspace, incident_reference, action_id)
        IncidentWrite.find!(workspace, incident_reference)
          .incident_actions.active.find(action_id.to_s)
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
