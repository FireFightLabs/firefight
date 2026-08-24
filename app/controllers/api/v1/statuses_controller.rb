class Api::V1::StatusesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_STATUSES, Ability::Action::ACTION_READ)
    @statuses = current_workspace.incident_statuses.active.ordered.includes(:incident_lifecycle_stage)
  end
end
