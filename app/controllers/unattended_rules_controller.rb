# The changes a team lets Halon make on its own. Part of who may do what, so the admins who hand out abilities and
# approval rules decide them too.
class UnattendedRulesController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: :update, delete: :destroy
  before_action :set_rule, only: [ :update, :destroy ]

  def create
    rule = current_workspace.unattended_rules.create!(rule_attributes.merge(created_by: current_membership))
    redirect_to halon_on_call_path, notice: "Unattended rule to #{rule.change_words} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: halon_on_call_path, inertia: { errors: e.record.errors.to_hash }
  end

  # The switch on a row sends only enabled, the dialog the whole rule.
  def update
    if @rule.update(rule_attributes)
      redirect_to halon_on_call_path, notice: updated_notice
    else
      redirect_back fallback_location: halon_on_call_path, inertia: { errors: @rule.errors.to_hash }
    end
  end

  def destroy
    blocked = @rule.delete_blocked_reason
    return redirect_to halon_on_call_path, alert: blocked if blocked

    @rule.destroy!
    redirect_to halon_on_call_path, notice: "Unattended rule to #{@rule.change_words} was deleted."
  end

  private

  def set_rule
    @rule = current_workspace.unattended_rules.find(params[:id])
  end

  def updated_notice
    return "Unattended rule to #{@rule.change_words} was updated." unless @rule.saved_change_to_enabled? && @rule.saved_changes.keys.excluding("enabled", "updated_at").empty?

    "Unattended rule to #{@rule.change_words} is #{@rule.enabled? ? 'on' : 'off'}."
  end

  def rule_attributes
    Ability::UnattendedRule.changes_from(current_workspace, params.require(:rule).permit(:capability, :resource_id, :metric, :threshold, :minutes, :enabled))
  end
end
