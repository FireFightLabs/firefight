class IncidentSubscriptionsController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, read: %i[create destroy]

  def create
    incident = find_incident
    state = incident.subscribe!(current_membership)

    redirect_to incident_path(incident), notice: incident.subscription_notice(state)
  end

  def destroy
    incident = find_incident
    state = incident.unsubscribe!(current_membership)

    redirect_to incident_path(incident), notice: incident.subscription_notice(state)
  end

  private

  def find_incident
    current_workspace.incidents.find(params[:incident_id])
  end
end
