class Api::V1::StatusesController < Api::V1::ApiController
  include ApiManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_STATUSES, IncidentStatus

  private

  # A status belongs to one lifecycle stage, which is what decides whether it
  # means the incident is live, closed or canceled.
  def extra_attributes
    return {} if params[:lifecycle_stage].blank?

    { incident_lifecycle_stage: IncidentLifecycleStage.find_by!(key: params[:lifecycle_stage]) }
  end
end
