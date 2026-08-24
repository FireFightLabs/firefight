class AlertRoutingController < InertiaController
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
    routed = tester.evaluate(params.fetch(:fields, {}).to_unsafe_h)
    return render json: { error: "No alert routing policy configured" }, status: :unprocessable_entity unless routed

    render json: {
      matched: routed.matched?,
      outcome: routed.outcome,
      context: routed.context,
      trace: routed.trace,
      resolution: routed.matched? ? tester.preview(routed) : nil
    }
  end

  # Delivers one labeled test message to the resolved notify target so the
  # user can verify the bot can actually reach it. Re-evaluates server-side.
  # The client never picks the destination.
  def send_test
    routed = tester.evaluate(params.fetch(:fields, {}).to_unsafe_h)
    return render json: { error: "No alert routing policy configured" }, status: :unprocessable_entity unless routed

    result = tester.deliver(routed)
    return render json: { error: result.error }, status: :unprocessable_entity unless result.sent

    render json: { sent: true, notify: result.notify }
  end

  private

  def tester
    @tester ||= AlertRoutingTestService.new(current_workspace, routing_scope)
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
