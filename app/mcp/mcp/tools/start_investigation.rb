module Mcp
  module Tools
    class StartInvestigation < Base
      tool_name START_INVESTIGATION
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
      description "Start Halon investigating an incident. It runs in the background for minutes, reads " \
                  "what Firefight and the connected tools know, records its theories and every step, and " \
                  "posts its finding in the incident's channel. Poll get_investigation to follow it. One " \
                  "investigation runs per incident at a time, and a second request is told which one is " \
                  "running. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" }
        },
        required: [ "incident" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        blocked = Investigation.unavailable_reason(workspace) || incident.investigation_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked) if blocked

        started = InvestigationService.new(workspace).start(
          incident, trigger_source: Investigation::TRIGGER_MCP, triggered_by: principal
        )
        return Mcp::ToolDispatcher.error_response(Investigation.already_running_message(incident)) unless started

        respond(InvestigationPayloads.summary(started))
      end
    end
  end
end
