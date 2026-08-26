module Mcp
  module Tools
    class ReopenIncident < Base
      tool_name REOPEN_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Reopen an incident that was resolved or canceled, putting it back on this " \
                  "workspace's default live status. Not form-driven: give the reason it is coming " \
                  "back, which the channel sees. If the call requires approval, retry the identical " \
                  "call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          reason: { type: "string", description: "Why it is being reopened, posted to the channel" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        return Mcp::ToolDispatcher.error_response("#{incident.identifier} is already active.") unless incident.terminal?

        IncidentLifecycleService.new(workspace).change_status(
          incident,
          { incident_status: workspace.default_live_status },
          changed_by: principal,
          message: args[:reason].presence
        )

        respond(SearchIncidents.summary(incident.reload).merge(reopened: true))
      end
    end
  end
end
