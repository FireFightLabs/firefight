class Api::V1::SeveritiesController < Api::V1::ApiController
  include ApiManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_SEVERITIES, IncidentSeverity

  private

  def extra_attributes
    params[:rank].present? ? { rank: params[:rank] } : {}
  end
end
