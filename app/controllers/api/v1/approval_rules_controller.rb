class Api::V1::ApprovalRulesController < Api::V1::ApiController
  before_action :set_rule, only: [ :update, :destroy, :move_up, :move_down ]

  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @rules = current_workspace.approval_rules
  end

  def create
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)
    @rule = current_workspace.find_or_create_approval_policy!.append_rule!(rule_attributes)
    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @rule.update!(rule_attributes)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)
    @rule.destroy!
    head :no_content
  end

  def move_up
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @rule.swap_priority_with!(@rule.policy.ordered_rules.where("priority < ?", @rule.priority).last)
    render :show
  end

  def move_down
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @rule.swap_priority_with!(@rule.policy.ordered_rules.where("priority > ?", @rule.priority).first)
    render :show
  end

  private

  def set_rule
    @rule = current_workspace.approval_rules.find(params[:id])
  end

  def rule_attributes
    PolicyRule::ApprovalRuleChanges.attributes(
      workspace: current_workspace, existing: @rule,
      changes: params.permit(:enabled, :approver_role, :self_approval, :notify, abilities: [], risk_levels: [], environments: [], approvers: [])
    )
  end
end
