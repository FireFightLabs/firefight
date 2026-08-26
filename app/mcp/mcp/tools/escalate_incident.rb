module Mcp
  module Tools
    class EscalateIncident < Base
      tool_name ESCALATE_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Ask a specific person to pick this incident up. Firefight posts the ask in the " \
                  "incident channel, messages them directly with an acknowledge button, and chases " \
                  "them if they do not answer. This is how you pull a human in rather than " \
                  "carrying on alone. An incident that is over cannot be escalated. If the call " \
                  "requires approval, retry the identical call with approval_id once approved. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          member: { type: "string", description: "Email or platform user id of the person to pull in" },
          reason: { type: "string", description: "Why you need them, shown in the ask" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "member", "reason" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        target = ActionItemWrite.member_for(workspace, args[:member])

        event = IncidentLifecycleService.new(workspace).escalate(
          incident, escalated_to: target, reason: args[:reason].to_s, changed_by: principal
        )

        respond(
          incident: incident.identifier,
          escalated_to: target.actor_display_name,
          reason: event.metadata["reason"],
          acknowledged: false
        )
      end
    end
  end
end
