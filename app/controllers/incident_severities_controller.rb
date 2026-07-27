class IncidentSeveritiesController < InertiaController
  include ManagesConfigurableOptions

  private

  def option_model
    IncidentSeverity
  end

  def options_path
    settings_severities_path
  end
end
