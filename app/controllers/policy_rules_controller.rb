class PolicyRulesController < InertiaController
  authorizes Ability::Action::RESOURCE_POLICIES, create: :create, update: %i[update move_up move_down], delete: :destroy
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
    scope =
      if params[:alert_source_id].present?
        current_workspace.alert_sources.find(params[:alert_source_id])
      else
        current_workspace
      end
    scope.find_or_create_alert_routing_policy!
  end

  def swap_with(other)
    @rule.swap_priority_with!(other)
    redirect_to routing_path_for(@rule.policy)
  end

  def routing_path_for(policy)
    settings_alert_routing_path(source_id: policy.scoped_to_id)
  end

  def rule_params
    params.require(:rule).permit(
      :enabled,
      outcome: [
        :action, :severity_id,
        { notify: [ :type, :channel_id, :channel_name, :member_id, :entry_id, :of ] },
        { invite: [ :type, :member_id, :entry_id, :of ] }
      ],
      conditions: [ :field, :operator, :value, { value: [] } ]
    )
  end
end
