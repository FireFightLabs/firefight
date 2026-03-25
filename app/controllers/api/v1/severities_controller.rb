class Api::V1::SeveritiesController < Api::V1::ApiController
  def index
    authorize!("severities", "read")
    @severities = current_workspace.incident_severities.active.ordered
  end
end
