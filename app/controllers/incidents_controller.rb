class IncidentsController < InertiaController
  before_action :require_authentication

  def show
    incident = current_workspace.incidents
      .with_detail_associations
      .find(params[:id])

    render inertia: "incidents/show", props: {
      incident: IncidentDetailSerializer.one(incident),
      timelineEvents: InertiaRails.defer {
        TimelineEventSerializer.many(
          incident.incident_events.chronological.includes(user: :user, eventable: nil)
        )
      },
      actions: InertiaRails.defer {
        IncidentActionSerializer.many(
          incident.incident_actions.active.includes(assignee: :user, created_by: :user)
        )
      },
      hasPostmortem: incident.postmortem.present?
    }
  end

  def postmortem
    render inertia: "incidents/postmortem"
  end
end
