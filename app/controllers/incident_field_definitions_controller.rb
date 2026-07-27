class IncidentFieldDefinitionsController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_field_definition, only: [ :update, :disable, :enable, :destroy ]

  def create
    field_definition_service.create(**field_definition_params)
    redirect_to settings_custom_fields_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_custom_fields_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  def update
    field_definition_service.update(@field_definition, field_definition_update_params)
    redirect_to settings_custom_fields_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_custom_fields_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  def disable
    @field_definition.update!(deleted_at: Time.current)
    redirect_to settings_custom_fields_path, notice: "#{@field_definition.name} was disabled."
  end

  def enable
    @field_definition.update!(deleted_at: nil)
    redirect_to settings_custom_fields_path, notice: "#{@field_definition.name} was enabled."
  end

  def destroy
    if @field_definition.deletion_blocked_reason
      return redirect_to settings_custom_fields_path, alert: @field_definition.deletion_blocked_reason
    end

    @field_definition.destroy!
    redirect_to settings_custom_fields_path, notice: "#{@field_definition.name} was deleted."
  end

  def reorder
    IncidentFieldDefinition.reorder!(current_workspace, params.require(:ordered_ids))
    redirect_to settings_custom_fields_path, notice: "Custom field order updated."
  end

  private

  def set_field_definition
    @field_definition = current_workspace.incident_field_definitions.find(params[:id])
  end

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
