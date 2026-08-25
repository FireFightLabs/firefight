class IncidentRolesController < InertiaController
  include ManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_INCIDENT_ROLES

  private

  def option_model
    IncidentRole
  end

  def options_path
    settings_roles_path
  end
end
