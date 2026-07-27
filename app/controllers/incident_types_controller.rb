class IncidentTypesController < InertiaController
  include ManagesConfigurableOptions

  private

  def option_model
    IncidentType
  end

  def options_path
    settings_types_path
  end
end
