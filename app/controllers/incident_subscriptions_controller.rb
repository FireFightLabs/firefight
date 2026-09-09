class IncidentSubscriptionsController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, read: %i[create destroy]

  def create
    incident = find_incident
    incident.subscribe!(current_membership)

    redirect_to incident_path(incident),
      notice: "You are subscribed to #{incident.identifier}. Every update Firefight posts about it will reach you as a direct message."
  end

  def destroy
    incident = find_incident
    incident.unsubscribe!(current_membership)

    redirect_to incident_path(incident), notice: "You are no longer subscribed to #{incident.identifier}."
  end

  private

  def find_incident
    current_workspace.incidents.find(params[:incident_id])
  end
end
