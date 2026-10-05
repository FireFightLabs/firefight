module Mcp
  module Tools
    class CreateActionItemIssue < Base
      tool_name CREATE_ACTION_ITEM_ISSUE
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Open an issue for an action item in the workspace's issue tracker, the same as a person pressing " \
                  "\"Create issue\" on the item, or try again after its issue failed. The issue carries the item's title, " \
                  "the incident's identifier and a link back to the incident, and is opened as you, through your " \
                  "permissions and approval rules. It arrives in a moment: read it from get_incident, where an item " \
                  "shows its issue's key and link, or why it is missing. Refused when the item already has one or the " \
                  "workspace opens none. Get the item's id from get_incident. Docs: #{Docs::INCIDENTS}"
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
        refusal = IssueSyncService.new(workspace).request(action, by: principal)
        return Mcp::ToolDispatcher.error_response(refusal) if refusal

        respond(ActionItemWrite.summary(action.reload))
      end
    end
  end
end
