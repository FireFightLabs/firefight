module Mcp
  module Tools
    class UpsertApprovalRule < Base
      extend GatewayPayloads

      tool_name UPSERT_APPROVAL_RULE
      description "Create or update an approval rule, which holds matching calls until an " \
                  "approver says yes. Pass id to update; omit it to append a new rule. Only the " \
                  "keys given change. Empty abilities, risk_levels or environments match " \
                  "everything on that axis. Rules apply first match wins. Docs: #{Docs::APPROVALS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          id: { type: "string", description: "Rule id to update; omit to create" },
          abilities: { type: "array", items: { type: "string" }, description: "Ability keys the rule holds" },
          risk_levels: { type: "array", items: { type: "string" }, description: "read, write or destructive" },
          environments: { type: "array", items: { type: "string" }, description: "Environment slugs" },
          approver_role: { type: "string", description: "admin or owner, asked when no approvers are named" },
          approvers: { type: "array", items: { type: "string" }, description: "Ids of the people who may decide, from list_principals" },
          notify: { type: "string", description: "channel, dm or both" },
          self_approval: { type: "boolean", description: "Whether the requester may approve their own request (default true)" },
          enabled: { type: "boolean", description: "Switch the rule off without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.authorization(workspace, args)
        action = existing_rule(workspace, args) ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE
        [ Ability::Action::RESOURCE_PERMISSIONS, action ]
      end

      def self.perform(workspace:, args:)
        existing = existing_rule(workspace, args)
        raise ActiveRecord::RecordNotFound if args[:id].present? && existing.nil?

        attributes = PolicyRule::ApprovalRuleChanges.attributes(
          workspace: workspace, existing: existing, changes: args.except(:id, :approval_id)
        )
        rule = existing ? existing.tap { |record| record.update!(attributes) } : workspace.find_or_create_approval_policy!.append_rule!(attributes)

        respond(approval_rule_payload(rule))
      end

      def self.existing_rule(workspace, args)
        return nil if args[:id].blank?

        workspace.approval_rules.find_by(id: args[:id].to_s)
      end
    end
  end
end
