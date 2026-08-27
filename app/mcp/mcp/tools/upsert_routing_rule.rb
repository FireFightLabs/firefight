module Mcp
  module Tools
    class UpsertRoutingRule < Base
      tool_name UPSERT_ROUTING_RULE
      description "Create or update an alert routing rule. A rule matching the given priority " \
                  "is updated; otherwise a new rule is created (at that priority, or appended " \
                  "when priority is omitted). Dry-run first with evaluate_routing. Pass source " \
                  "to edit that source's policy; omit it for the workspace default. If the call " \
                  "requires approval, retry the identical call with approval_id once approved. " \
                  "Docs: #{Docs::ROUTING_RULES}"
      annotations(**WRITE)
      input_schema(
        properties: {
          source: { type: "string", description: "Alert source name; omit for the workspace policy" },
          priority: { type: "integer", description: "Rule priority; omit to append at the end" },
          conditions: {
            type: "array",
            description: "Conditions, e.g. [{\"field\": \"service\", \"operator\": \"is_one_of\", \"value\": [\"checkout\"]}]",
            items: { type: "object" }
          },
          outcome: {
            type: "object",
            description: "Outcome, e.g. {\"action\": \"auto_create_incident\", \"severity_id\": \"...\"}"
          },
          enabled: { type: "boolean", description: "Disable a rule without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.authorization(workspace, args)
        action = existing_rule(workspace, args) ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE
        [ Ability::Action::RESOURCE_POLICIES, action ]
      end

      def self.perform(workspace:, args:)
        policy = routing_policy(workspace, args)

        attributes = {}
        attributes[:conditions] = args[:conditions].map(&:to_h) if args.key?(:conditions)
        attributes[:outcome] = args[:outcome].to_h if args.key?(:outcome)
        attributes[:enabled] = args[:enabled] unless args[:enabled].nil?

        rule = args[:priority].present? ? policy.policy_rules.find_by(priority: args[:priority]) : nil
        if rule
          rule.update!(attributes)
        else
          priority = args[:priority].presence || (policy.policy_rules.maximum(:priority) || 0) + 1
          rule = policy.policy_rules.create!(attributes.merge(priority: priority))
        end

        respond(rule_payload(rule))
      end

      def self.routing_policy(workspace, args)
        routing_scope(workspace, args).find_or_create_alert_routing_policy!
      end

      def self.routing_scope(workspace, args)
        return workspace if args[:source].blank?

        workspace.alert_sources.find_by!(name: args[:source].to_s)
      end

      # Side-effect-free (runs before authorization). Looks up the existing
      # policy/rule without materializing anything.
      def self.existing_rule(workspace, args)
        return nil if args[:priority].blank?

        scope = args[:source].present? ? workspace.alert_sources.find_by(name: args[:source].to_s) : workspace
        scope&.alert_routing_policy&.policy_rules&.find_by(priority: args[:priority])
      end

      def self.rule_payload(rule)
        { priority: rule.priority, conditions: rule.conditions, outcome: rule.outcome, enabled: rule.enabled }
      end
    end
  end
end
