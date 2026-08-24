class Api::V1::CustomFieldsController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_CUSTOM_FIELDS, Ability::Action::ACTION_READ)
    @custom_fields = current_workspace.incident_field_definitions.active.ordered
  end
end
