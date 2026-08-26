module Mcp
  module Tools
    class CompleteActionItem < Base
      tool_name COMPLETE_ACTION_ITEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Mark a piece of work done. The channel message is struck through and the " \
                  "completion is announced, the same as a person pressing \"Mark as done\". Get " \
                  "the item's id from get_incident. If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
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
        blocked_reason = action.completion_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked_reason) if blocked_reason

        IncidentActionService.new(workspace).complete_action(action: action, completed_by: principal)

        respond(ActionItemWrite.summary(action.reload))
      end
    end
  end
end
