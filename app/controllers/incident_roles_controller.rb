class IncidentRolesController < InertiaController
  include ManagesConfigurableOptions

  private

  def option_model
    IncidentRole
  end

  def options_path
    settings_roles_path
  end
end
