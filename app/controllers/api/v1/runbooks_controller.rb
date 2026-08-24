class Api::V1::RunbooksController < Api::V1::ApiController
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_runbook, only: [ :show ]

  def index
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ)
    @runbooks = current_workspace.runbooks.active.ordered.includes(:runbook_steps)
  end

  def show
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ)
  end

  private

  def set_runbook
    scope = current_workspace.runbooks.active.includes(:runbook_steps)
    @runbook = if params[:id].to_s.match?(UUID_FORMAT)
      scope.find(params[:id])
    else
      scope.find_by!(slug: params[:id])
    end
  end
end
