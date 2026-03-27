class SettingsController < InertiaController
  before_action :require_authentication

  def index
    render inertia: "settings/index", props: {
      roles: IncidentRoleSerializer.many(
        current_workspace.incident_roles.ordered
      )
    }
  end
end
