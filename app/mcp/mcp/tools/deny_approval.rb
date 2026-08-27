module Mcp
  module Tools
    class DenyApproval < Base
      tool_name DENY_APPROVAL
      description "Deny a pending ability approval by id, as the connected human. Only " \
                  "personal tokens and OAuth connections can resolve approvals. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      authorize_as Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE
      input_schema(
        properties: {
          id: { type: "string", description: "Approval id" }
        },
        required: [ "id" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        resolve_approval(workspace, principal, args, :deny)
      end
    end
  end
end
