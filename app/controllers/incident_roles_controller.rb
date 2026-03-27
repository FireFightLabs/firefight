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
      redirect_to settings_path(tab: "roles")
    else
      redirect_back fallback_location: settings_path(tab: "roles"), inertia: { errors: role.errors.to_hash }
    end
  end

  def disable
    return redirect_to settings_path(tab: "roles") if @role.slug == "incident_lead"

    @role.update!(deleted_at: Time.current)
    redirect_to settings_path(tab: "roles")
  end

  def enable
    @role.update!(deleted_at: nil)
    redirect_to settings_path(tab: "roles")
  end

  def destroy
    return redirect_to settings_path(tab: "roles") if @role.slug == "incident_lead"
    return redirect_to settings_path(tab: "roles") if @role.incident_role_assignments.exists?

    @role.destroy!
    redirect_to settings_path(tab: "roles")
  end

  private

  def set_role
    @role = current_workspace.incident_roles.find(params[:id])
  end
end
