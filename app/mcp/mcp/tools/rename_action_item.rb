module Mcp
  module Tools
    class RenameActionItem < Base
      tool_name RENAME_ACTION_ITEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Change what a piece of work says needs doing. Its channel message shows the new title, and its issue " \
                  "takes it when the item is kept in step with one. Get the item's id from get_incident. If the call " \
                  "requires approval, retry the identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          action_item: { type: "string", description: "Action item id, from get_incident" },
          description: { type: "string", description: "The new title, in one line" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "action_item", "description" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        action = ActionItemWrite.find!(workspace, args[:incident], args[:action_item])
        refusal = IncidentActionService.new(workspace).rename_action(action: action, description: args[:description].to_s, renamed_by: principal)
        return Mcp::ToolDispatcher.error_response(refusal) if refusal

        respond(ActionItemWrite.summary(action.reload))
      end
    end
  end
end
