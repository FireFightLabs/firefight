class PolicyRulesController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_rule, only: [ :update, :destroy, :move_up, :move_down ]

  def create
    policy = find_or_create_policy
    rule = policy.policy_rules.new(rule_params)
    rule.priority = (policy.policy_rules.maximum(:priority) || 0) + 1

    if rule.save
      redirect_to routing_path_for(policy)
    else
      redirect_back fallback_location: settings_alert_routing_path, inertia: { errors: rule.errors.to_hash }
    end
  end

  def update
    if @rule.update(rule_params)
      redirect_to routing_path_for(@rule.policy)
    else
      redirect_back fallback_location: settings_alert_routing_path, inertia: { errors: @rule.errors.to_hash }
    end
  end

  def destroy
    @rule.destroy!
    redirect_to routing_path_for(@rule.policy)
  end

  def move_up
    swap_with(@rule.policy.ordered_rules.where("priority < ?", @rule.priority).last)
  end

  def move_down
    swap_with(@rule.policy.ordered_rules.where("priority > ?", @rule.priority).first)
  end

  private

  def set_rule
    @rule = PolicyRule.joins(:policy).where(policies: { workspace_id: current_workspace.id }).find(params[:id])
  end

  def find_or_create_policy
    if params[:alert_source_id].present?
      current_workspace.alert_sources.find(params[:alert_source_id]).find_or_create_routing_policy!
    else
      current_workspace.find_or_create_alert_routing_fallback_policy!
    end
  end

  def swap_with(other)
    if other
      PolicyRule.transaction do
        a, b = @rule.priority, other.priority
        # Two-step through a temporary priority to satisfy the unique index.
        @rule.update_columns(priority: -1)
        other.update_columns(priority: a)
        @rule.update_columns(priority: b)
      end
    end
    redirect_to routing_path_for(@rule.policy)
  end

  def routing_path_for(policy)
    if policy.scoped_to_type == AlertSource.name
      settings_alert_routing_path(source_id: policy.scoped_to_id)
    else
      settings_alert_routing_path
    end
  end

  def rule_params
    params.require(:rule).permit(
      :enabled,
      outcome: [
        :action, :severity_id,
        { notify: [ :type, :channel_id, :member_id, :entry_id, :of ] },
        { invite: [ :type, :member_id, :entry_id, :of ] }
      ],
      conditions: [ :field, :operator, :value, { value: [] } ]
    )
  end
end
