class Api::V1::RunbooksController < Api::V1::ApiController
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_runbook, only: %i[show update destroy]

  def index
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ)
    @runbooks = current_workspace.runbooks.active.ordered.includes(:runbook_steps)
  end

  def show
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ)
  end

  # Steps and conditions are only touched when they are sent, so changing a
  # summary never silently clears the procedure.
  def create
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_CREATE)

    @runbook = Runbook::Upsert.new(current_workspace).call(nil, runbook_params)
    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_UPDATE)

    @runbook = Runbook::Upsert.new(current_workspace).call(@runbook, runbook_params)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_DELETE)

    blocked_reason = @runbook.deletion_blocked_reason
    return render json: error_response("validation_error", blocked_reason), status: :unprocessable_entity if blocked_reason

    @runbook.destroy!
    head :no_content
  end

  private

  def runbook_params
    params.permit(
      :name, :summary, :content, :external_url,
      steps: [ :title, :instruction ],
      conditions: [ :condition_field, :operator, :custom_field, values: [] ]
    ).to_h.deep_symbolize_keys
  end

  def set_runbook
    scope = current_workspace.runbooks.active.includes(:runbook_steps)
    @runbook = if params[:id].to_s.match?(UUID_FORMAT)
      scope.find(params[:id])
    else
      scope.find_by!(slug: params[:id])
    end
  end
end
