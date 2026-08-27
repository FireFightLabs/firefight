module Mcp
  module Tools
    class UpdateRoutingConfig < Base
      tool_name UPDATE_ROUTING_CONFIG
      description "Update alert grouping config on the routing policy: the grouping window " \
                  "and which alert fields must match for alerts to group into one incident. " \
                  "Omitted knobs are left untouched; an empty content_match_fields list reverts " \
                  "to the default. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::ROUTING_RULES}"
      annotations(**WRITE)
      authorize_as Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_UPDATE
      input_schema(
        properties: {
          source: { type: "string", description: "Alert source name; omit for the workspace policy" },
          grouping_window_minutes: { type: "integer", description: "Minutes within which matching alerts group (#{Policy::AlertRoutingConfig::WINDOW_MINUTES_RANGE.min}-#{Policy::AlertRoutingConfig::WINDOW_MINUTES_RANGE.max})" },
          content_match_fields: {
            type: "array", items: { type: "string" },
            description: "Alert fields that must match for grouping, e.g. [\"service\"]"
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = args[:source].present? ? workspace.alert_sources.find_by!(name: args[:source].to_s) : workspace
        policy = scope.find_or_create_alert_routing_policy!

        policy.update!(domain_config: policy.domain_config_merging(
          window_minutes: args[:grouping_window_minutes],
          match_fields: args[:content_match_fields]
        ))

        respond(
          grouping_window_minutes: policy.grouping_window_minutes,
          content_match_fields: policy.content_match_fields
        )
      end
    end
  end
end
