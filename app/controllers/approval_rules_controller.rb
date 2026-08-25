# Approval rules are part of Permissions. The same admins who hand out
# abilities decide which of them wait for a second look.
class ApprovalRulesController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: %i[update move_up move_down], delete: :destroy
  before_action :set_rule, only: [ :update, :destroy, :move_up, :move_down ]

  def create
    current_workspace.find_or_create_approval_policy!.append_rule!(rule_attributes)
    redirect_to gateway_permissions_path, notice: "Approval rule was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: gateway_permissions_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    if @rule.update(rule_attributes)
      redirect_to gateway_permissions_path, notice: "Approval rule was updated."
    else
      redirect_back fallback_location: gateway_permissions_path, inertia: { errors: @rule.errors.to_hash }
    end
  end

  def destroy
    @rule.destroy!
    redirect_to gateway_permissions_path, notice: "Approval rule was deleted."
  end

  def move_up
    @rule.swap_priority_with!(@rule.policy.ordered_rules.where("priority < ?", @rule.priority).last)
    redirect_to gateway_permissions_path, notice: "Approval rule was moved up."
  end

  def move_down
    @rule.swap_priority_with!(@rule.policy.ordered_rules.where("priority > ?", @rule.priority).first)
    redirect_to gateway_permissions_path, notice: "Approval rule was moved down."
  end

  private

  def set_rule
    @rule = current_workspace.approval_rules.find(params[:id])
  end

  # The dialog sends the whole rule, with environments by id. An
  # enable/disable toggle sends only `enabled`.
  def rule_attributes
    PolicyRule::ApprovalRuleChanges.attributes(
      workspace: current_workspace, existing: @rule,
      changes: params.require(:rule).permit(
        :enabled, :approver_role, :self_approval, :notify, :agents_may_approve,
        abilities: [], risk_levels: [], environment_ids: [], approvers: [ :kind, :id ]
      )
    )
  end
end
