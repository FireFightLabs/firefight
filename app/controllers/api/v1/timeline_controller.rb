# The incident's timeline as data, every recorded event in order. It includes
# the milestones Firefight noted from the channel, so an agent can learn how
# an incident was debugged without reading a message of it.
class Api::V1::TimelineController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)

    @incident = incident
    @events, @pagination = paginate(@incident.incident_events.undismissed.chronological.includes(:actor))
  end

  def dismiss
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    @incident = incident
    @event = @incident.incident_events.find(params[:id])
    @event.dismiss!(by: Current.principal)

    render :event
  rescue IncidentEvent::NotDismissable => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def incident
    current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
  end
end
