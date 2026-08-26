class Api::V1::IncidentTypesController < Api::V1::ApiController
  include ApiManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_INCIDENT_TYPES, IncidentType
end
