module Mcp
  module Tools
    class ApproveApproval < Base
      tool_name APPROVE_APPROVAL
      description "Approve a pending ability approval by id, as the connected human. Only " \
                  "personal tokens and OAuth connections can resolve approvals — the approver " \
                  "is re-validated (role now, requester rules) at this moment. The requester " \
                  "then retries their parked call with approval_id. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      authorize_as ApiKey::RESOURCE_APPROVALS, ApiKey::ACTION_UPDATE
      input_schema(
        properties: {
          id: { type: "string", description: "Approval id" }
        },
        required: [ "id" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        resolve_approval(workspace, principal, args, :approve)
      end
    end
  end
end
