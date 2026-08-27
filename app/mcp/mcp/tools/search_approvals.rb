module Mcp
  module Tools
    class SearchApprovals < Base
      tool_name SEARCH_APPROVALS
      description "Search this workspace's ability approvals: calls parked behind an approval " \
                  "policy, who requested them, and how they resolved. Poll your own approval " \
                  "id here after a call parks, then retry the identical call with approval_id " \
                  "once approved. Newest first. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      authorize_as Ability::Action::RESOURCE_APPROVALS
      input_schema(
        properties: {
          status: { type: "string", description: "pending, approved, denied or expired; omit for all" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = workspace.ability_approvals.order(created_at: :desc)
        scope = scope.where(status: args[:status].to_s) if args[:status].present?
        approvals, truncated = capped(scope, args)

        respond(
          approvals: approvals.map { |approval| approval_payload(approval) },
          truncated: truncated
        )
      end

      def self.approval_payload(approval)
        {
          id: approval.id,
          principal: approval.principal_label,
          action_key: approval.action_key,
          scope: approval.scope,
          params: approval.params,
          required_role: approval.required_role,
          self_approvable: approval.self_approvable,
          approvers: Ability::Principal.references(approval.approver_ids),
          agents_may_approve: approval.agents_may_approve,
          status: approval.status,
          approver: approval.approver&.actor_display_name,
          requested_at: approval.created_at.iso8601,
          resolved_at: approval.resolved_at&.iso8601
        }.compact
      end
    end
  end
end
