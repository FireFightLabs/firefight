class AlertRoutingController < InertiaController
  before_action :require_authentication

  def update
    policy = find_or_create_policy(scoped_source)

    if policy.update(enabled: params.dig(:policy, :enabled))
      redirect_to settings_alert_routing_path(source_id: params[:alert_source_id].presence)
    else
      redirect_back fallback_location: settings_alert_routing_path, inertia: { errors: policy.errors.to_hash }
    end
  end

  # Route tester: pure evaluation with a full trace, zero side effects.
  # Mirrors ingest resolution: the source's policy with workspace fallback.
  def test
    policy = routing_policy
    return render json: { error: "No alert routing policy configured" }, status: :unprocessable_entity unless policy

    # Free-form field hash; only ever fed to pure evaluation, never assigned to a model.
    fields = params.fetch(:fields, {}).to_unsafe_h
    context = Policy::ContextBuilder.build(workspace: current_workspace, fields: fields)
    result = policy.evaluate(context)

    render json: {
      matched: result.matched?,
      outcome: result.outcome,
      context: context,
      trace: result.trace,
      resolution: result.matched? ? resolution_preview(result.outcome, fields) : nil
    }
  end

  # Delivers one labeled test message to the resolved notify target so the
  # user can verify the bot can actually reach it. Re-evaluates server-side —
  # the client never picks the destination.
  def send_test
    policy = routing_policy
    return render json: { error: "No alert routing policy configured" }, status: :unprocessable_entity unless policy

    fields = params.fetch(:fields, {}).to_unsafe_h
    result = policy.evaluate(Policy::ContextBuilder.build(workspace: current_workspace, fields: fields))
    target = result.matched? ? result.outcome["notify"] : nil
    return render json: { error: "The test fields must match a rule with a notify target" }, status: :unprocessable_entity if target.blank?

    resolver = Alert::TargetResolver.new(current_workspace, fields)
    channel = resolver.channel_for(target)
    return render json: { error: resolver.notes.last || "The notify target could not be resolved" }, status: :unprocessable_entity if channel.blank?

    WorkspaceAdapter.for(current_workspace).post_routing_test_message(
      channel_id: channel,
      description: "your test alert matched rule #{result.matched_rule.priority} and this conversation would be notified"
    )
    render json: { sent: true, notify: notify_label(target, resolver) }
  rescue AdapterError => e
    render json: { error: "Delivery failed: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def routing_policy
    if scoped_source
      scoped_source.effective_routing_policy
    else
      current_workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).workspace_wide.first
    end
  end

  # Dry-run target resolution so the tester shows who would actually be
  # invited/notified. Pure lookups plus one best-effort Slack channel-name
  # lookup for display; nothing is posted.
  def resolution_preview(outcome, fields)
    resolver = Alert::TargetResolver.new(current_workspace, fields)
    invitees = resolver.memberships_for(outcome["invite"]).map { |m| m.user.name }
    notify = notify_label(outcome["notify"], resolver)

    { invite: invitees, notify: notify, notes: resolver.notes }
  end

  def notify_label(target, resolver)
    resolved = resolver.channel_for(target)
    return nil if resolved.blank?

    if target&.dig("type") == PolicyRule::AlertRoutingOutcome::TARGET_MEMBER
      member = current_workspace.workspace_memberships.find_by(id: target["member_id"])
      return member ? "#{member.user.name} (DM)" : resolved
    end

    channel = channel_name(resolved)
    channel ? "##{channel}" : resolved
  end

  def channel_name(channel_id)
    WorkspaceAdapter.for(current_workspace).list_channels.find { |c| c[:id] == channel_id }&.dig(:name)
  rescue AdapterError
    nil
  end

  def scoped_source
    return nil if params[:alert_source_id].blank?

    @scoped_source ||= current_workspace.alert_sources.find(params[:alert_source_id])
  end

  def find_or_create_policy(source)
    if source
      source.routing_policy ||
        current_workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Alert routing", scoped_to: source)
    else
      current_workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).workspace_wide.first ||
        current_workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Alert routing")
    end
  end
end
