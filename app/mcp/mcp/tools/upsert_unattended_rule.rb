module Mcp
  module Tools
    class UpsertUnattendedRule < Base
      tool_name UPSERT_UNATTENDED_RULE
      description "Create or update an unattended rule, a change Halon may make on its own when an alert started its " \
                  "investigation, its fix proposes exactly that change and a fresh reading of the metric is above the threshold. " \
                  "The rule grants nothing, Halon also needs a grant of the tool the change runs through. Pass id to update, and " \
                  "only the keys given change, so enabled alone turns a rule on or off. Omit id to create. Docs: #{Docs::ON_CALL}"
      annotations(**WRITE)
      input_schema(
        properties: {
          id: { type: "string", description: "Rule id to update, omit to create" },
          capability: { type: "string", enum: Ability::UnattendedRule::CAPABILITIES, description: "The change Halon may make" },
          resource: { type: "string", description: "The resource on the map, by its id there, its name or its provider's id" },
          metric: { type: "string", enum: Ability::UnattendedRule::METRICS, description: "The metric read before acting" },
          threshold: { type: "number", description: "Halon acts only when the metric's average is above this, in the provider's units" },
          minutes: { type: "integer", description: "Minutes the average is taken over (default #{Ability::UnattendedRule::DEFAULT_MINUTES})" },
          enabled: { type: "boolean", description: "Switch the rule off without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.authorization(workspace, args)
        action = existing_rule(workspace, args) ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE
        [ Ability::Action::RESOURCE_PERMISSIONS, action ]
      end

      def self.perform_with_principal(workspace:, principal:, args:)
        existing = existing_rule(workspace, args)
        raise ActiveRecord::RecordNotFound if args[:id].present? && existing.nil?

        changes = Ability::UnattendedRule.changes_from(workspace, args.except(:id, :approval_id))
        rule = existing || workspace.unattended_rules.new(created_by: (principal if principal.is_a?(WorkspaceMembership)))
        rule.update!(changes)
        respond(rule.payload)
      rescue ActiveRecord::RecordInvalid => e
        Mcp::ToolDispatcher.error_response(e.record.errors.full_messages.to_sentence)
      end

      def self.existing_rule(workspace, args)
        return nil if args[:id].blank?

        workspace.unattended_rules.find_by(id: args[:id].to_s)
      end
    end
  end
end
