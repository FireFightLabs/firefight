# Delivers the route tester's "Send test message": re-evaluates the policy,
# resolves the notify target server-side, and posts one labeled message via
# the adapter. A service because it crosses into the platform adapter.
class AlertRoutingTestService
  Result = Struct.new(:sent, :target, :error, keyword_init: true)

  def initialize(workspace)
    @workspace = workspace
  end

  def deliver(policy, fields)
    result = policy.evaluate(Policy::ContextBuilder.build(workspace: @workspace, fields: fields))
    target = result.matched? ? result.outcome["notify"] : nil
    return Result.new(sent: false, error: "The test fields must match a rule with a notify target") if target.blank?

    resolver = Alert::TargetResolver.new(@workspace, fields)
    channel = resolver.channel_for(target)
    return Result.new(sent: false, error: resolver.notes.last || "The notify target could not be resolved") if channel.blank?

    WorkspaceAdapter.for(@workspace).post_routing_test_message(
      channel_id: channel,
      description: "your test alert matched rule #{result.matched_rule.priority} and this conversation would be notified"
    )
    Result.new(sent: true, target: target)
  rescue AdapterError => e
    Result.new(sent: false, error: "Delivery failed: #{e.message}")
  end
end
