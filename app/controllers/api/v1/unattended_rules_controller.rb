# The changes a team lets Halon make on its own, as on Halon, On-call. Part of who may do what, so admin-only like
# approval rules.
class Api::V1::UnattendedRulesController < Api::V1::ApiController
  before_action :set_rule, only: [ :update, :destroy ]

  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @rules = current_workspace.unattended_rules.with_usage_counts.includes(:resource, :created_by).order(:created_at)
  end

  def create
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)
    @rule = current_workspace.unattended_rules.create!(rule_attributes.merge(created_by: (Current.principal if Current.principal.is_a?(WorkspaceMembership))))
    render :show, status: :created
  end

  # Takes only the keys given, so enabled alone turns a rule on or off.
  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @rule.update!(rule_attributes)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)
    blocked = @rule.delete_blocked_reason
    return render json: error_response("validation_error", blocked), status: :unprocessable_entity if blocked

    @rule.destroy!
    head :no_content
  end

  private

  def set_rule
    @rule = current_workspace.unattended_rules.find(params[:id])
  end

  def rule_attributes
    Ability::UnattendedRule.changes_from(current_workspace, params.permit(:capability, :resource, :metric, :threshold, :minutes, :enabled))
  end
end
