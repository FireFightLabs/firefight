module Mcp
  module Tools
    class ReopenActionItem < Base
      tool_name REOPEN_ACTION_ITEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Open a piece of work that was marked done again. Whoever held it holds it again, and its issue reopens " \
                  "when the item is kept in step with one. Refused for an action once the incident is over. Get the item's " \
                  "id from get_incident. If the call requires approval, retry the identical call with approval_id once " \
                  "approved. Docs: #{Docs::INCIDENTS}"
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
        refusal = IncidentActionService.new(workspace).reopen_action(action: action, reopened_by: principal)
        return Mcp::ToolDispatcher.error_response(refusal) if refusal

        respond(ActionItemWrite.summary(action.reload))
      end
    end
  end
end
