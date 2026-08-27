class IncidentEventsController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, update: :dismiss

  def dismiss
    incident = current_workspace.incidents.find(params[:incident_id])
    event = incident.incident_events.find(params[:id])
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    event.dismiss!(by: member)

    redirect_to incident_path(incident), notice: "The note was dismissed."
  rescue IncidentEvent::NotDismissable => e
    redirect_to incident_path(incident), alert: e.message
  end
end
