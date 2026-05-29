class Api::V1::CustomFieldsController < Api::V1::ApiController
  def index
    authorize!(ApiKey::RESOURCE_CUSTOM_FIELDS, ApiKey::ACTION_READ)
    @custom_fields = current_workspace.incident_field_definitions.active.ordered
  end
end
