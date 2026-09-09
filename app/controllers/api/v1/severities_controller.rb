class Api::V1::SeveritiesController < Api::V1::ApiController
  include ApiManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_SEVERITIES, IncidentSeverity
end
