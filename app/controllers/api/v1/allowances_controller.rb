# What Halon may do without asking in any chat, as under Settings, Workspace. Part of who may do what, so admin-only like
# approval rules, and set only by a person in Firefight. A token reads the list and changes none of it.
class Api::V1::AllowancesController < Api::V1::ApiController
  before_action :set_allowance, only: [ :update, :destroy ]
  before_action :refuse_token_changes, except: :index

  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @allowances = current_workspace.allowances.with_usage_counts.includes(:environment, :created_by, :integration, action: :source).order(:created_at)
  end

  def create
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)
    @allowance = current_workspace.allowances.create!(allowance_attributes)
    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    @allowance.update!(allowance_attributes)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)
    blocked = @allowance.delete_blocked_reason
    return render json: error_response("validation_error", blocked), status: :unprocessable_entity if blocked

    @allowance.destroy!
    head :no_content
  end

  private

  def refuse_token_changes
    refusal = Ability::Allowance.change_blocked_reason(AbilityGateway::SOURCE_API)
    render json: error_response("token_refused", refusal), status: :unprocessable_entity if refusal
  end

  def set_allowance
    @allowance = current_workspace.allowances.find(params[:id])
  end

  def allowance_attributes
    Ability::Allowance.changes_from(current_workspace, params.permit(:capability, :action_key, :integration, :environment, :enabled))
  end
end
