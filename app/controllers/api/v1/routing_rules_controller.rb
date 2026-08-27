# Alert routing rules, which decide what an incoming alert does. Rules belong
# to a scope, either the workspace or one alert source, and are addressed by
# priority within it. A source with no policy of its own falls back to the
# workspace, so writing a rule for a source is what gives it one.
class Api::V1::RoutingRulesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_READ)

    policy = scope.alert_routing_policy
    @rules = policy ? policy.policy_rules.order(:priority) : []
    render :index
  end

  def create
    authorize!(Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_CREATE)

    policy = scope.find_or_create_alert_routing_policy!
    @rule = policy.policy_rules.create!(rule_attributes.merge(priority: next_priority(policy)))

    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_UPDATE)

    @rule = existing_rule!
    @rule.update!(rule_attributes)

    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_DELETE)

    existing_rule!.destroy!
    head :no_content
  end

  private

  def rule_attributes
    attributes = {}
    attributes[:conditions] = Array(params[:conditions]).map { |c| c.to_unsafe_h } if params.key?(:conditions)
    attributes[:outcome] = params[:outcome].to_unsafe_h if params.key?(:outcome)
    attributes[:enabled] = ActiveModel::Type::Boolean.new.cast(params[:enabled]) unless params[:enabled].nil?
    attributes
  end

  def next_priority(policy)
    (policy.policy_rules.maximum(:priority) || 0) + 1
  end

  def existing_rule!
    policy = scope.alert_routing_policy or raise ActiveRecord::RecordNotFound
    policy.policy_rules.find_by!(priority: params[:id])
  end

  # No source names the workspace itself, which is the fallback every source
  # without a policy of its own uses.
  def scope
    return current_workspace if params[:source].blank?

    current_workspace.alert_sources.find_by!(name: params[:source])
  end
end
