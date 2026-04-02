class IncidentTypesController < InertiaController
  before_action :require_authentication
  before_action :set_incident_type, only: [ :update, :destroy ]

  def create
    max_position = current_workspace.incident_types.maximum(:position) || 0

    incident_type = current_workspace.incident_types.new(
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      color: params[:color],
      is_default: ActiveModel::Type::Boolean.new.cast(params[:is_default]) || false,
      position: max_position + 1
    )

    if incident_type.save
      redirect_to settings_types_path
    else
      redirect_back fallback_location: settings_types_path, inertia: { errors: incident_type.errors.to_hash }
    end
  end

  def update
    attrs = {
      name: params[:name],
      description: params[:description],
      color: params[:color],
      is_default: ActiveModel::Type::Boolean.new.cast(params[:is_default])
    }.compact

    if @incident_type.update(attrs)
      redirect_to settings_types_path
    else
      redirect_back fallback_location: settings_types_path, inertia: { errors: @incident_type.errors.to_hash }
    end
  end

  def destroy
    if @incident_type.incidents.where(deleted_at: nil).exists?
      @incident_type.update!(deleted_at: Time.current)
    else
      @incident_type.destroy!
    end

    redirect_to settings_types_path
  end

  private

  def set_incident_type
    @incident_type = current_workspace.incident_types.find(params[:id])
  end
end
