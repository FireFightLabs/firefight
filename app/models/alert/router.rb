# One routing evaluation for a scope, an alert source or the workspace: the
# scope's effective policy, the fields it exposes to rules, the
# catalog-enriched context, and the evaluation itself. Ingest, the route
# tester, the test-message sender, and MCP's dry run all route through here,
# so a change to what rules can see happens in one place.
#
# Pure lookups, no writes and no platform calls.
class Alert::Router
  Result = Struct.new(:policy, :fields, :context, :evaluation, keyword_init: true) do
    def matched?
      evaluation.matched?
    end

    def outcome
      evaluation.outcome
    end

    def matched_rule
      evaluation.matched_rule
    end

    def trace
      evaluation.trace
    end
  end

  def initialize(workspace, scope)
    @workspace = workspace
    @scope = scope
  end

  # nil when the scope has no enabled policy, so callers answer "not
  # configured" instead of evaluating against nothing.
  def policy
    return @policy if defined?(@policy)

    @policy = @scope.effective_alert_routing_policy
  end

  def route(raw_fields)
    return nil unless policy

    fields = @scope.routing_fields(raw_fields)
    context = Policy::ContextBuilder.build(workspace: @workspace, fields: fields)
    Result.new(policy: policy, fields: fields, context: context, evaluation: policy.evaluate(context))
  end
end
