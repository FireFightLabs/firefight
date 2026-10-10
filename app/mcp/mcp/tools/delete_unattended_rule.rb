module Mcp
  module Tools
    class DeleteUnattendedRule < Base
      tool_name DELETE_UNATTENDED_RULE
      description "Delete an unattended rule by id. A rule Halon already acted under is refused with the reason, and is " \
                  "switched off with upsert_unattended_rule instead. Docs: #{Docs::ON_CALL}"
      annotations(**DESTRUCTIVE)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE
      input_schema(
        properties: {
          id: { type: "string", description: "Id of the rule to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "id" ]
      )

      def self.perform(workspace:, args:)
        rule = workspace.unattended_rules.find(args[:id].to_s)
        blocked = rule.delete_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked) if blocked

        rule.destroy!
        respond(id: rule.id, deleted: true)
      end
    end
  end
end
