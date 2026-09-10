# Ingest, the route tester, the test sender and MCP's dry run all route through here,
# so what rules can see changes in one place. No writes, no platform calls.
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

  # nil when the scope has no enabled policy, so callers answer "not configured".
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
