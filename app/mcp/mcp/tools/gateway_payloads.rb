module Mcp
  module Tools
    module GatewayPayloads
      def grant_payload(grant)
        {
          id: grant.id,
          principal: { kind: grant.principal.actor_kind, id: grant.principal_id, name: grant.principal.actor_display_name },
          ability: grant.action&.key,
          permission_set: grant.role&.slug,
          environments: grant.workspace.environment_entries.where(id: grant.environment_ids).pluck(:slug),
          expires_at: grant.expires_at&.utc&.iso8601,
          expired: grant.expired?,
          no_access: grant.no_access?
        }.compact
      end

      def permission_set_payload(set)
        { slug: set.slug, name: set.name, description: set.description, built_in: set.built_in?, abilities: set.actions.map(&:key).sort,
          grant_count: set.grants.size }
      end

      # One connection's row of Who can do what. names is the members by id, from the same overview.
      def member_access_payload(connection, names)
        people = ->(ids) { ids.filter_map { |id| names[id] }.map { |member| { id: member.id, name: member.display_name } } }
        standing = lambda do |row|
          { permission_set: row.role.slug, choice: row.choice, people: people.call(row.people_ids), left_out: people.call(row.left_out_ids),
            through: row.through.map { |access| { permission_set: access.role_slug, name: access.role_name, people: people.call(access.people_ids) } },
            unavailable_reason: row.role.member_access_unavailable_reason }
        end
        { connection: { id: connection.integration.id, name: connection.integration.display_name },
          read: standing.call(connection.read), change: standing.call(connection.change) }
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
          approvers: Ability::Principal.references(requirement["approvers"]),
          agents_may_approve: requirement.fetch("agents_may_approve", false),
          on_call: requirement.fetch(PolicyRule::ApprovalOutcome::ON_CALL, false),
          notify: requirement["notify"] || PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL,
          self_approval: requirement.fetch("self_approval", true)
        }
      end
    end
  end
end
