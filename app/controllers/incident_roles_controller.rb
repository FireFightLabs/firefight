class IncidentRolesController < InertiaController
  before_action :require_authentication
  before_action :set_role, only: [ :disable, :enable, :destroy ]

  def create
    max_position = current_workspace.incident_roles.maximum(:position) || 0

    role = current_workspace.incident_roles.new(
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      position: max_position + 1
    )

    if role.save
      redirect_to settings_roles_path
    else
      redirect_back fallback_location: settings_roles_path, inertia: { errors: role.errors.to_hash }
    end
  end

  def disable
    return redirect_to settings_roles_path if @role.slug == IncidentRole::SLUG_INCIDENT_LEAD

    @role.update!(deleted_at: Time.current)
    redirect_to settings_roles_path
  end

  def enable
    @role.update!(deleted_at: nil)
    redirect_to settings_roles_path
  end

  def destroy
    return redirect_to settings_roles_path if @role.slug == IncidentRole::SLUG_INCIDENT_LEAD
    return redirect_to settings_roles_path if @role.incident_role_assignments.exists?

    @role.destroy!
    redirect_to settings_roles_path
  end

  private

  def set_role
    @role = current_workspace.incident_roles.find(params[:id])
  end
end
