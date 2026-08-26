module Mcp
  module Tools
    class ClaimRunbookStep < Base
      tool_name CLAIM_RUNBOOK_STEP
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Take one step of a runbook attached to an incident, which creates the action " \
                  "item behind it, or hands over the one that already exists. Leave member out to " \
                  "take it yourself. Get the runbook and step ids from get_incident. If the call " \
                  "requires approval, retry the identical call with approval_id once approved. " \
                  "Docs: #{Docs::RUNBOOKS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          runbook: { type: "string", description: "Attached runbook id, from get_incident" },
          step: { type: "string", description: "Runbook step id, from get_incident" },
          member: { type: "string", description: "Email or platform user id to hand it to; omit to take it yourself" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "runbook", "step" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        attachment = incident.incident_runbooks.find(args[:runbook].to_s)
        step = attachment.runbook.runbook_steps.find(args[:step].to_s)

        action = IncidentActionService.new(workspace).assign_step(
          incident: incident,
          runbook_step: step,
          assignee: workspace.workspace_memberships.resolve!(args[:member]) || principal,
          assigned_by: principal
        )

        respond(ActionItemWrite.summary(action).merge(runbook: attachment.runbook.name, step: step.title))
      end
    end
  end
end
