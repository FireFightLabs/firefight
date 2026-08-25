module Mcp
  module Tools
    class SearchActivity < Base
      tool_name SEARCH_ACTIVITY
      description "The gateway's audit log: every call to a connected tool, every configuration " \
                  "change and every refused or waiting request, with who made it and from where. " \
                  "Newest first. Docs: #{Docs::ACTIVITY}"
      annotations(**READ_ONLY)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS
      input_schema(
        properties: {
          decision: { type: "string", description: "allow, deny or pending; omit for all" },
          ability: { type: "string", description: "Exact ability key to filter on" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = workspace.ability_invocations.order(created_at: :desc)
        scope = scope.where(decision: args[:decision].to_s) if args[:decision].present?
        scope = scope.where(action_key: args[:ability].to_s) if args[:ability].present?
        invocations, truncated = capped(scope, args)

        respond(
          activity: invocations.map do |invocation|
            {
              id: invocation.id, principal: invocation.principal_label, source: invocation.source,
              ability: invocation.action_key, decision: invocation.decision, outcome: invocation.outcome,
              error: invocation.error_summary, duration_ms: invocation.duration_ms,
              at: invocation.created_at.utc.iso8601
            }.compact
          end,
          truncated: truncated
        )
      end
    end
  end
end
