class IncidentTypesController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_incident_type, only: [ :update, :destroy ]

  def create
    incident_type = current_workspace.incident_types.new(
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      color: params[:color],
      is_default: ActiveModel::Type::Boolean.new.cast(params[:is_default]) || false
    )

    incident_type.save_in_position!
    redirect_to settings_types_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_types_path, inertia: { errors: incident_type.errors.to_hash }
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

  # Always soft-delete via deleted_at so destroy semantics match severities,
  # statuses, and roles (admin can disable then re-enable from the UI). The
  # previous behavior conditionally hard-deleted when no incidents referenced
  # the type, which was inconsistent and harder for the UI to reason about.
  def destroy
    @incident_type.update!(deleted_at: Time.current)
    redirect_to settings_types_path
  end

  private

  def set_incident_type
    @incident_type = current_workspace.incident_types.find(params[:id])
  end
end
