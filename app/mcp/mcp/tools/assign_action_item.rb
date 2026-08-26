module Mcp
  module Tools
    class AssignActionItem < Base
      tool_name ASSIGN_ACTION_ITEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Take a piece of work, or hand it to someone else. Leave member out to take it " \
                  "yourself, which is what a person does with the \"I can take this\" button. " \
                  "Naming someone else announces the handover in the channel. Get the item's id " \
                  "from get_incident. If the call requires approval, retry the identical call " \
                  "with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          action_item: { type: "string", description: "Action item id, from get_incident" },
          member: { type: "string", description: "Email or platform user id to hand it to; omit to take it yourself" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "action_item" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        action = ActionItemWrite.find!(workspace, args[:incident], args[:action_item])

        IncidentActionService.new(workspace).assign_action(
          action: action,
          assignee: workspace.workspace_memberships.resolve!(args[:member]) || principal,
          assigned_by: principal
        )

        respond(ActionItemWrite.summary(action.reload))
      end
    end
  end
end
