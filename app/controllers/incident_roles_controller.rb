class IncidentRolesController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_role, only: [ :disable, :enable, :destroy ]

  def create
    role = current_workspace.incident_roles.new(
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description]
    )

    role.save_in_position!
    redirect_to settings_roles_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_roles_path, inertia: { errors: e.record.errors.to_hash }
  end

  def disable
    if @role.slug == IncidentRole::SLUG_INCIDENT_LEAD
      return redirect_to settings_roles_path, alert: "The Incident Lead role can't be disabled."
    end

    @role.update!(deleted_at: Time.current)
    redirect_to settings_roles_path
  end

  def enable
    @role.update!(deleted_at: nil)
    redirect_to settings_roles_path
  end

  def destroy
    if @role.slug == IncidentRole::SLUG_INCIDENT_LEAD
      return redirect_to settings_roles_path, alert: "The Incident Lead role can't be deleted."
    end
    if @role.incident_role_assignments.exists?
      return redirect_to settings_roles_path, alert: "Can't delete a role that's assigned to incidents. Disable it instead."
    end

    @role.destroy!
    redirect_to settings_roles_path
  end

  private

  def set_role
    @role = current_workspace.incident_roles.find(params[:id])
  end
end
