module Mcp
  module Tools
    class StartPostmortem < Base
      tool_name START_POSTMORTEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Start the postmortem for an incident that has been resolved. Leave generate out " \
                  "to open an empty one you write yourself with update_postmortem. Pass generate " \
                  "true to have Firefight draft it from the incident first, which takes a moment " \
                  "and comes back with generation_state \"generating\", so poll get_postmortem " \
                  "until it is done. An incident that is still open or was canceled is refused, " \
                  "with the reason. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          generate: { type: "boolean", description: "true drafts it from the incident, false or omitted opens an empty one" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        blocked_reason = incident.postmortem_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked_reason) if blocked_reason

        return respond(PostmortemPayloads.summary(Postmortem.start_blank!(incident, by: principal))) unless args[:generate]

        generate(workspace, incident, principal)
      end

      def self.generate(workspace, incident, principal)
        return Mcp::ToolDispatcher.error_response("AI features are not available.") unless defined?(FirefightAi)

        gate = Entitlements.check(workspace, Entitlements::AI)
        return Mcp::ToolDispatcher.error_response(gate.message) if gate.blocked?

        postmortem = Postmortem.start_generation!(incident, by: principal)
        PostmortemGenerationJob.perform_later(incident.id) if postmortem

        respond(PostmortemPayloads.summary(incident.reload.postmortem))
      end
      private_class_method :generate
    end
  end
end
