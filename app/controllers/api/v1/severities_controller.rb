class Api::V1::SeveritiesController < Api::V1::ApiController
  def index
    authorize!(ApiKey::RESOURCE_SEVERITIES, ApiKey::ACTION_READ)
    @severities = current_workspace.incident_severities.active.ordered
  end
end
