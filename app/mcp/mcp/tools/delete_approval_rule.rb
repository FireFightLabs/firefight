module Mcp
  module Tools
    class DeleteApprovalRule < Base
      tool_name DELETE_APPROVAL_RULE
      description "Delete an approval rule by id. Calls it used to hold run without waiting " \
                  "from then on. Docs: #{Docs::APPROVALS}"
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
        workspace.approval_rules.find(args[:id].to_s).destroy!
        respond(id: args[:id], deleted: true)
      end
    end
  end
end
