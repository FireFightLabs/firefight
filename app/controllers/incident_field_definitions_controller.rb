class IncidentFieldDefinitionsController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_field_definition, only: [ :update, :disable, :enable, :destroy ]

  def create
    field_definition = field_definition_service.create(field_definition_params)
    redirect_to settings_custom_fields_path, notice: "#{field_definition.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_custom_fields_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  def update
    field_definition_service.update(@field_definition, field_definition_params)
    redirect_to settings_custom_fields_path, notice: "#{@field_definition.reload.name} was updated."
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
      catalog_type_id: params[:catalog_type_id].presence,
      options: option_params
    }
  end

  # Options arrive in display order. An entry keeps its id across a rename, so
  # the incidents pointing at it are never touched.
  def option_params
    Array(params[:options]).filter_map do |option|
      # A form-encoded empty list arrives as "", not an empty array.
      next unless option.respond_to?(:permit)

      permitted = option.permit(:id, :label, :disabled)
      label = permitted[:label].to_s.strip
      next if label.blank?

      { id: permitted[:id].presence, label: label, disabled: permitted[:disabled] }
    end
  end
end
