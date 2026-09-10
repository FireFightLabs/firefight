# Server side of the route tester. A service because it reaches the platform
# adapter, for channel names on preview and for the test delivery itself.
class AlertRoutingTestService
  Result = Struct.new(:sent, :notify, :error, keyword_init: true)

  def initialize(workspace, scope)
    @workspace = workspace
    @scope = scope
  end

  def evaluate(raw_fields)
    Alert::Router.new(@workspace, @scope).route(raw_fields)
  end

  # Resolves the target as ingest would. Nothing is posted.
  def preview(routed)
    resolver = Alert::TargetResolver.new(@workspace, routed.fields)
    invitees = resolver.memberships_for(routed.outcome["invite"]).map { |membership| membership.user.name }
    notify = notify_label(routed.outcome["notify"], resolver)

    { invite: invitees, notify: notify, notes: resolver.notes }
  end

  def deliver(routed)
    target = routed.matched? ? routed.outcome["notify"] : nil
    return Result.new(sent: false, error: "The test fields must match a rule with a notify target") if target.blank?

    resolver = Alert::TargetResolver.new(@workspace, routed.fields)
    channel = resolver.channel_for(target)
    return Result.new(sent: false, error: resolver.notes.last || "The notify target could not be resolved") if channel.blank?

    WorkspaceAdapter.for(@workspace).post_routing_test_message(
      channel_id: channel,
      description: "your test alert matched rule #{routed.matched_rule.priority} and this conversation would be notified"
    )
    Result.new(sent: true, notify: notify_label(target, resolver))
  rescue AdapterError => e
    Result.new(sent: false, error: "Delivery failed: #{e.message}")
  end

  private

  def notify_label(target, resolver)
    resolved = resolver.channel_for(target)
    return nil if resolved.blank?

    if target&.dig("type") == PolicyRule::AlertRoutingOutcome::TARGET_MEMBER
      member = @workspace.workspace_memberships.find_by(id: target["member_id"])
      return member ? "#{member.user.name} (DM)" : resolved
    end

    channel = channel_name(resolved)
    channel ? "##{channel}" : resolved
  end

  def channel_name(channel_id)
    WorkspaceAdapter.for(@workspace).list_channels.find { |channel| channel[:id] == channel_id }&.dig(:name)
  rescue AdapterError
    nil
  end
end
