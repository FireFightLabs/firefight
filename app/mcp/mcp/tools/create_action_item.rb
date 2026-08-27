module Mcp
  module Tools
    class CreateActionItem < Base
      tool_name CREATE_ACTION_ITEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Add a piece of work to an incident and post it to the channel, the same as a " \
                  "person running /ff action. kind \"action\" is work during the incident, " \
                  "\"followup\" is work after it. Leave member out to open it unassigned, or name " \
                  "a person to hand it straight to them. Call get_incident for the items already " \
                  "open. If the call requires approval, retry the identical call with approval_id " \
                  "once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          description: { type: "string", description: "What needs doing, in one line" },
          kind: { type: "string", enum: IncidentAction::ACTION_TYPES, description: "action (during) or followup (after)" },
          member: { type: "string", description: "Email or platform user id to assign it to; omit to leave it unassigned" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "description" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])

        action = IncidentActionService.new(workspace).create_action(
          incident: incident,
          created_by: principal,
          action_type: args[:kind].presence || IncidentAction::ACTION_TYPE_ACTION,
          description: args[:description].to_s,
          assignee: workspace.workspace_memberships.resolve!(args[:member])
        )

        respond(ActionItemWrite.summary(action))
      end
    end
  end
end
