module Mcp
  module Tools
    class UnassignActionItem < Base
      tool_name UNASSIGN_ACTION_ITEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Let go of a piece of work, so nobody holds it and it is open again for someone to take. Its issue is " \
                  "unassigned when the item is kept in step with one. Get the item's id from get_incident. If the call " \
                  "requires approval, retry the identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          action_item: { type: "string", description: "Action item id, from get_incident" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "action_item" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        action = ActionItemWrite.find!(workspace, args[:incident], args[:action_item])
        refusal = IncidentActionService.new(workspace).unassign_action(action: action, unassigned_by: principal)
        return Mcp::ToolDispatcher.error_response(refusal) if refusal

        respond(ActionItemWrite.summary(action.reload))
      end
    end
  end
end
