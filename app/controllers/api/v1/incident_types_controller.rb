class Api::V1::IncidentTypesController < Api::V1::ApiController
  def index
    authorize!(ApiKey::RESOURCE_INCIDENT_TYPES, ApiKey::ACTION_READ)
    @incident_types = current_workspace.incident_types.active.ordered
  end
end
