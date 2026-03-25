class Api::V1::IncidentTypesController < Api::V1::ApiController
  def index
    authorize!("incident_types", "read")
    @incident_types = current_workspace.incident_types.active.ordered
  end
end
