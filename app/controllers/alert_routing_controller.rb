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
    policy =
      if scoped_source
        scoped_source.effective_routing_policy
      else
        current_workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).workspace_wide.first
      end
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

  private

  # Dry-run target resolution so the tester shows who would actually be
  # invited/notified. Pure lookups, zero side effects.
  def resolution_preview(outcome, fields)
    resolver = Alert::TargetResolver.new(current_workspace, fields)
    invitees = resolver.memberships_for(outcome["invite"]).map { |m| m.user.name }
    notify = resolver.channel_for(outcome["notify"])

    { invite: invitees, notify: notify, notes: resolver.notes }
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
