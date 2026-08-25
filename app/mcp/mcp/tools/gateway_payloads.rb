module Mcp
  module Tools
    # The shapes the gateway tools answer with, shared so a grant reads the
    # same whether it came back from granting it or from listing a principal.
    module GatewayPayloads
      def grant_payload(grant)
        {
          id: grant.id,
          principal: { kind: grant.principal.actor_kind, id: grant.principal_id, name: grant.principal.actor_display_name },
          ability: grant.action&.key,
          permission_set: grant.role&.slug,
          environments: grant.workspace.environment_entries.where(id: grant.environment_ids).pluck(:slug),
          expires_at: grant.expires_at&.utc&.iso8601,
          expired: grant.expired?
        }.compact
      end

      def permission_set_payload(set)
        { slug: set.slug, name: set.name, abilities: set.actions.map(&:key).sort, grant_count: set.grants.size }
      end

      def approval_rule_payload(rule)
        requirement = PolicyRule::ApprovalOutcome.requirement(rule.outcome)
        environment_ids = PolicyRule::ApprovalConditions.values_for(rule.conditions, PolicyRule::ApprovalConditions::FIELD_ENVIRONMENT)
        {
          id: rule.id,
          priority: rule.priority,
          enabled: rule.enabled,
          abilities: PolicyRule::ApprovalConditions.values_for(rule.conditions, PolicyRule::ApprovalConditions::FIELD_ACTION_KEY),
          risk_levels: PolicyRule::ApprovalConditions.values_for(rule.conditions, PolicyRule::ApprovalConditions::FIELD_RISK_LEVEL),
          environments: rule.policy.workspace.environment_entries.where(id: environment_ids).pluck(:slug),
          approver_role: requirement["role"],
          approvers: Array(requirement["approvers"]),
          notify: requirement["notify"] || PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL,
          self_approval: requirement.fetch("self_approval", true)
        }
      end
    end
  end
end
