class IncidentSeveritiesController < InertiaController
  include ManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_SEVERITIES

  private

  def option_model
    IncidentSeverity
  end

  def options_path
    settings_severities_path
  end
end
