module Mcp
  module Tools
    class DeleteAllowance < Base
      tool_name FirefightTools::DELETE_ALLOWANCE
      description "Delete an entry of what Halon may do without asking, by id. An entry Halon already made a change under is " \
                  "refused with the reason, and is switched off with upsert_allowance instead. Docs: #{Docs::WITHOUT_ASKING}"
      annotations(**DESTRUCTIVE)
      ends_something
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE

      def self.token_refusal(_workspace, _args) = Ability::Allowance.change_blocked_reason(AbilityGateway::SOURCE_MCP)
      input_schema(
        properties: {
          id: { type: "string", description: "Id of the entry to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "id" ]
      )

      def self.perform(workspace:, args:)
        allowance = workspace.allowances.find(args[:id].to_s)
        blocked = allowance.delete_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked) if blocked

        allowance.destroy!
        respond(id: allowance.id, deleted: true)
      end
    end
  end
end
