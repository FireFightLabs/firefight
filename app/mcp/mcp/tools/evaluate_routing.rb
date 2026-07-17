module Mcp
  module Tools
    class EvaluateRouting < Base
      tool_name EVALUATE_ROUTING
      description "Dry-run alert routing: given hypothetical alert fields (e.g. service, " \
                  "event, severity), returns which rule would match, the outcome (create " \
                  "incident / notify / drop), and a per-condition trace. Pure evaluation — " \
                  "nothing is created or sent. Pass source to test that source's routing; " \
                  "omit it for the workspace default."
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          source: { type: "string", description: "Alert source name; omit for workspace default routing" },
          fields: {
            type: "object",
            description: "The alert fields to evaluate, e.g. {\"service\": \"checkout\", \"event\": \"container:crash\"}",
            additionalProperties: { type: "string" }
          }
        },
        required: [ "fields" ]
      )

      def self.perform(workspace:, args:)
        scope =
          if args[:source].present?
            workspace.alert_sources.find_by(name: args[:source]).tap do |source|
              raise ActiveRecord::RecordNotFound unless source
            end
          else
            workspace
          end
        policy = scope.effective_alert_routing_policy
        return Mcp::ToolDispatcher.error_response("No enabled alert routing policy configured for this scope.") unless policy

        fields = (args[:fields] || {}).transform_keys(&:to_s).transform_values(&:to_s)
        context = Policy::ContextBuilder.build(workspace: workspace, fields: fields)
        result = policy.evaluate(context)

        respond(
          matched: result.matched?,
          matched_rule_priority: result.matched_rule&.priority,
          outcome: result.outcome,
          context: context,
          trace: result.trace
        )
      end
    end
  end
end
