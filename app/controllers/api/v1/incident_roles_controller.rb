class Api::V1::IncidentRolesController < Api::V1::ApiController
  include ApiManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_INCIDENT_ROLES, IncidentRole
end
