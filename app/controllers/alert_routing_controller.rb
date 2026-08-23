class AlertRoutingController < InertiaController
  before_action :require_authentication
  before_action :require_admin!, only: [ :update, :send_test ]

  def update
    policy = routing_scope.find_or_create_alert_routing_policy!

    if policy.update(policy_attrs(policy))
      redirect_to settings_alert_routing_path(source_id: params[:alert_source_id].presence)
    else
      redirect_back fallback_location: settings_alert_routing_path, inertia: { errors: policy.errors.to_hash }
    end
  end

  # Route tester: pure evaluation with a full trace, zero side effects.
  # Mirrors ingest resolution, the source's policy with workspace fallback.
  def test
    policy = routing_policy
    return render json: { error: "No alert routing policy configured" }, status: :unprocessable_entity unless policy

    # Free-form field hash. Only ever fed to pure evaluation, never assigned to a model.
    fields = routing_scope.routing_fields(params.fetch(:fields, {}).to_unsafe_h)
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
  # user can verify the bot can actually reach it. Re-evaluates server-side.
  # The client never picks the destination.
  def send_test
    policy = routing_policy
    return render json: { error: "No alert routing policy configured" }, status: :unprocessable_entity unless policy

    fields = routing_scope.routing_fields(params.fetch(:fields, {}).to_unsafe_h)
    result = AlertRoutingTestService.new(current_workspace).deliver(policy, fields)
    return render json: { error: result.error }, status: :unprocessable_entity unless result.sent

    resolver = Alert::TargetResolver.new(current_workspace, fields)
    render json: { sent: true, notify: notify_label(result.target, resolver) }
  end

  private

  # The tester mirrors ingest, the scope's effective policy, enabled only.
  def routing_policy
    routing_scope.effective_alert_routing_policy
  end

  # Dry-run target resolution so the tester shows who would actually be
  # invited/notified. Pure lookups plus one best-effort Slack channel-name
  # lookup for display. Nothing is posted.
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

  def routing_scope
    scoped_source || current_workspace
  end

  def policy_attrs(policy)
    attrs = {}
    enabled = params.dig(:policy, :enabled)
    attrs[:enabled] = enabled unless enabled.nil?

    if params.dig(:policy, :grouping_window_minutes).present? || params[:policy]&.key?(:content_match_fields)
      attrs[:domain_config] = policy.domain_config_merging(
        window_minutes: params.dig(:policy, :grouping_window_minutes),
        match_fields: params[:policy]&.key?(:content_match_fields) ? Array(params.dig(:policy, :content_match_fields)) : nil
      )
    end

    attrs
  end
end
