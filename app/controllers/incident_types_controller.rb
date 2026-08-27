class IncidentTypesController < InertiaController
  include ManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_INCIDENT_TYPES

  private

  def option_model
    IncidentType
  end

  def options_path
    settings_types_path
  end
end
