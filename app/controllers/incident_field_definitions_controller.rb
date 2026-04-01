class IncidentFieldDefinitionsController < InertiaController
  before_action :require_authentication

  def create
    field_definition_service.create(**field_definition_params)
    redirect_to settings_custom_fields_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_custom_fields_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  def update
    field_definition = current_workspace.incident_field_definitions.active.find(params[:id])
    field_definition_service.update(field_definition, field_definition_update_params)
    redirect_to settings_custom_fields_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_custom_fields_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  private

  def field_definition_service
    @field_definition_service ||= IncidentFieldDefinitionService.new(current_workspace)
  end

  def field_definition_params
    {
      name: params.require(:name),
      description: params[:description],
      field_type: params.require(:field_type),
      option_source: params.require(:option_source),
      config: parsed_field_config
    }
  end

  def field_definition_update_params
    {
      name: params.require(:name),
      description: params[:description],
      field_type: params.require(:field_type),
      option_source: params.require(:option_source),
      config: parsed_field_config
    }
  end

  def parsed_field_config
    config = {}
    config["options"] = Array(params[:options]).map(&:presence).compact if params[:options].present?
    config["catalog_type_id"] = params[:catalog_type_id] if params[:catalog_type_id].present?
    config
  end
end
