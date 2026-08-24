class Api::V1::IncidentTypesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_INCIDENT_TYPES, Ability::Action::ACTION_READ)
    @incident_types = current_workspace.incident_types.active.ordered
  end
end
