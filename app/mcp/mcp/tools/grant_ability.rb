module Mcp
  module Tools
    class GrantAbility < Base
      extend GatewayPayloads

      tool_name GRANT_ABILITY
      description "Grant one ability or one permission set to a person, agent or service key, " \
                  "optionally limited to environments and with an expiry. Granting the same " \
                  "target again replaces its environments and expiry. Find principals with " \
                  "list_principals and ability keys with list_abilities. Docs: #{Docs::PERMISSIONS}"
      annotations(**WRITE)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE
      input_schema(
        properties: {
          principal_kind: { type: "string", description: "user, agent or api_key" },
          principal_id: { type: "string", description: "The principal's id" },
          ability: { type: "string", description: "Ability key to grant; give this or permission_set" },
          permission_set: { type: "string", description: "Permission set slug to grant; give this or ability" },
          environments: { type: "array", items: { type: "string" }, description: "Environment slugs; omit for every environment" },
          expires_at: { type: "string", description: "ISO 8601 time the grant lapses; omit for no expiry" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "principal_kind", "principal_id" ]
      )

      def self.perform(workspace:, args:)
        principal = Ability::Principal.find!(workspace, args[:principal_kind], args[:principal_id].to_s)
        target =
          if args[:permission_set].present?
            { role: workspace.ability_roles.find_by!(slug: args[:permission_set].to_s) }
          else
            { action: Ability::Action.grantable_for(workspace).find_by!(key: args[:ability].to_s) }
          end
        grant = Ability::Grant.grant!(
          workspace: workspace, principal: principal, target: target,
          environment_ids: PolicyRule::ApprovalRuleChanges.environment_ids(workspace, args[:environments]),
          expires_at: args[:expires_at]
        )

        respond(grant_payload(grant))
      end
    end
  end
end
