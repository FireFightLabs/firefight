class Api::V1::SeveritiesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_SEVERITIES, Ability::Action::ACTION_READ)
    @severities = current_workspace.incident_severities.active.ordered
  end
end
