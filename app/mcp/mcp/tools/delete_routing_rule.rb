module Mcp
  module Tools
    class DeleteRoutingRule < Base
      tool_name DELETE_ROUTING_RULE
      description "Delete an alert routing rule by priority. Pass source for that source's " \
                  "policy; omit it for the workspace default. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::ROUTING_RULES}"
      annotations(**DESTRUCTIVE)
      authorize_as Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_DELETE
      input_schema(
        properties: {
          source: { type: "string", description: "Alert source name; omit for the workspace policy" },
          priority: { type: "integer", description: "Priority of the rule to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "priority" ]
      )

      def self.perform(workspace:, args:)
        scope = args[:source].present? ? workspace.alert_sources.find_by!(name: args[:source].to_s) : workspace
        policy = scope.alert_routing_policy
        rule = policy&.policy_rules&.find_by(priority: args[:priority])
        raise ActiveRecord::RecordNotFound unless rule

        rule.destroy!
        respond(priority: args[:priority], deleted: true)
      end
    end
  end
end
